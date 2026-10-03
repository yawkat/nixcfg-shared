#!/usr/bin/env python3
"""Update flake.lock with a cooldown on third-party inputs.

Each direct GitHub input is pinned to a version at least COOLDOWN_DAYS old, so
a malicious commit has time to be noticed before we pick it up. Inputs owned
by EXEMPT_OWNER update to their latest commit. Inputs pulled in through
another input (e.g. llm-agents' own nixpkgs) are pinned by that input's lock
file and so can't be newer than the commit chosen for it.

nixpkgs on a nixos-YY.MM[-small] channel is pinned to the newest channel
release published before the cutoff, going by the release's upload time on
releases.nixos.org. That only ever picks revisions Hydra tested and cached.

Other inputs are pinned to the newest commit on the first-parent history of
their branch whose commit date is before the cutoff. First-parent keeps us off
commits that only exist on merged PR branches. The commit date only
approximates when a commit became visible on the branch: a committer can
backdate it.

Commits the updated lock file. When run in GitHub Actions, writes a PR body
to the step output `body` if anything changed. Requires git and nix. Run from
the flake directory.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

RELEASES_BUCKET = "https://nix-releases.s3.amazonaws.com"
RELEASES_URL = "https://releases.nixos.org"
S3_NS = {"s3": "http://s3.amazonaws.com/doc/2006-03-01/"}


def run(*args):
    return subprocess.run(
        args, check=True, capture_output=True, text=True
    ).stdout.strip()


def fetch(url):
    with urllib.request.urlopen(url) as resp:
        return resp.read()


def channel_releases(channel):
    """Return (upload time, key) for each release of a nixos channel, oldest first."""
    m = re.fullmatch(r"nixos-(\d+\.\d+)(-small)?", channel)
    if not m:
        sys.exit(f"nixpkgs: don't know where to find the history of channel {channel}")
    prefix = f"nixos/{m[1]}{m[2] or ''}/"
    releases = []
    token = None
    while True:
        query = {"list-type": "2", "prefix": prefix, "delimiter": "/"}
        if token:
            query["continuation-token"] = token
        root = ET.fromstring(
            fetch(f"{RELEASES_BUCKET}/?{urllib.parse.urlencode(query)}")
        )
        for obj in root.iterfind("s3:Contents", S3_NS):
            modified = obj.findtext("s3:LastModified", namespaces=S3_NS)
            releases.append(
                (
                    datetime.fromisoformat(modified.replace("Z", "+00:00")),
                    obj.findtext("s3:Key", namespaces=S3_NS),
                )
            )
        if root.findtext("s3:IsTruncated", namespaces=S3_NS) != "true":
            break
        token = root.findtext("s3:NextContinuationToken", namespaces=S3_NS)
    if not releases:
        sys.exit(f"nixpkgs: no releases found under {prefix}")
    return sorted(releases)


def nixpkgs_rev(channel, locked, cutoff):
    releases = channel_releases(channel)
    eligible = [r for r in releases if r[0] <= cutoff]
    if not eligible:
        sys.exit(f"nixpkgs: no {channel} release before {cutoff:%Y-%m-%dT%H:%M:%SZ}")
    chosen = eligible[-1]

    # Never move backwards if the lock already holds a newer release, e.g.
    # from a manual update with the cooldown set to 0.
    for release in releases:
        short_rev = release[1].rsplit(".", 1)[-1]
        if locked["rev"].startswith(short_rev) and release > chosen:
            return locked["rev"]

    return fetch(f"{RELEASES_URL}/{chosen[1]}/git-revision").decode().strip()


def first_parent_rev(owner, repo, ref, locked, cutoff):
    # Never move backwards if the lock already holds something newer, e.g.
    # from a manual update with the cooldown set to 0.
    if datetime.fromtimestamp(locked["lastModified"], timezone.utc) > cutoff:
        return ref, locked["rev"]

    with tempfile.TemporaryDirectory() as tmp:
        # Commits only: no trees or blobs are needed to walk the history.
        branch_args = ["--branch", ref] if ref else []
        run("git", "clone", "--quiet", "--bare", "--filter=tree:0",
            "--single-branch", *branch_args,
            f"https://github.com/{owner}/{repo}.git", tmp)  # fmt: skip
        ref = ref or run("git", "-C", tmp, "symbolic-ref", "--short", "HEAD")
        until = f"{cutoff:%Y-%m-%dT%H:%M:%SZ}"
        rev = run("git", "-C", tmp, "rev-list", "--first-parent", "-1",
                  f"--before={until}", "HEAD")  # fmt: skip
    if not rev:
        sys.exit(f"{owner}/{repo}: no commit on {ref} before {until}")
    return ref, rev


def override_args(lock, cutoff, exempt_owner):
    nodes = lock["nodes"]
    args = []
    for name, node_name in nodes[lock["root"]]["inputs"].items():
        node = nodes[node_name]
        original, locked = node["original"], node["locked"]
        if (
            original["type"] != "github"
            or original["owner"].lower() == exempt_owner.lower()
        ):
            continue
        owner, repo, ref = original["owner"], original["repo"], original.get("ref")
        if (owner.lower(), repo.lower()) == ("nixos", "nixpkgs"):
            rev = nixpkgs_rev(ref, locked, cutoff)
        else:
            ref, rev = first_parent_rev(owner, repo, ref, locked, cutoff)

        print(f"{name}: {owner}/{repo}/{ref or 'HEAD'} -> {rev}", file=sys.stderr)
        args += ["--override-input", name, f"github:{owner}/{repo}/{rev}"]
    return args


def main():
    cooldown_days = float(os.environ.get("COOLDOWN_DAYS", "5"))
    exempt_owner = os.environ.get("EXEMPT_OWNER", "yawkat")
    cutoff = datetime.now(timezone.utc) - timedelta(days=cooldown_days)

    with open("flake.lock") as f:
        lock = json.load(f)

    before = run("git", "rev-parse", "HEAD")
    subprocess.run(
        [
            "nix",
            "flake",
            "update",
            *override_args(lock, cutoff, exempt_owner),
            "--commit-lock-file",
            "--option",
            "commit-lockfile-summary",
            "flake update",
        ],
        check=True,
    )
    if run("git", "rev-parse", "HEAD") == before:
        print("Nothing to update.", file=sys.stderr)
        return

    changes = run("git", "log", "-1", "--format=%b")
    body = (
        f"Third-party inputs are pinned to versions at least {cooldown_days:g} days old; "
        f"{exempt_owner}/ inputs are at their latest.\n\n"
        f"```\n{changes}\n```\n\n"
        "GitHub Actions does not run workflows on PRs opened with GITHUB_TOKEN. "
        "**Close and reopen this PR to run CI.**\n"
    )
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as f:
            f.write(f"body<<EOF\n{body}EOF\n")
    else:
        print(body)


if __name__ == "__main__":
    main()
