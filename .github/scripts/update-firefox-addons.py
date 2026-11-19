#!/usr/bin/env python3
"""Bump the Firefox add-on pins in home/firefox.nix to their newest AMO release.

Every `firefoxAddon { ... }` block is looked up on addons.mozilla.org by its
addonId. The newest listed version that is at least --cooldown-days old
replaces the pinned version, url and hash. AMO publishes each file's sha256,
so no download and no Nix are needed. A pin is never moved backwards: only
versions AMO lists as newer than the pinned one are considered.

Writes a Markdown summary of the bumps to --summary (for the PR body).
"""

import argparse
import base64
import datetime
import json
import re
import sys
import urllib.parse
import urllib.request

API = "https://addons.mozilla.org/api/v5/addons/addon/{}/versions/?page_size=50"
BLOCK = re.compile(r"(\w+) = firefoxAddon \{\n(.*?)\n  \};", re.DOTALL)
# Give up looking for the pinned version after this many pages (50 each).
MAX_PAGES = 4


def field(block, name):
    m = re.search(rf'^    {name} = "([^"]*)";$', block, re.MULTILINE)
    if not m:
        raise ValueError(f"no {name} in block:\n{block}")
    return m.group(1)


def set_field(block, name, value):
    return re.sub(
        rf'^(    {name} = )"[^"]*";$',
        lambda m: f'{m.group(1)}"{value}";',
        block,
        count=1,
        flags=re.MULTILINE,
    )


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "nixcfg-addon-updater"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def newer_versions(addon_id, pinned):
    """AMO's listed Firefox versions newer than `pinned`, newest first."""
    url = API.format(urllib.parse.quote(addon_id, safe=""))
    found = []
    for _ in range(MAX_PAGES):
        page = fetch(url)
        for v in page["results"]:
            if v["version"] == pinned:
                return found
            if "firefox" in v["compatibility"] and v["file"]["status"] == "public":
                found.append(v)
        url = page["next"]
        if not url:
            break
    raise RuntimeError(
        f"{addon_id}: pinned version {pinned} not among AMO's recent listed "
        "versions; refusing to guess whether newer releases are an upgrade"
    )


def license_name(version):
    name = (version.get("license") or {}).get("name") or "none listed"
    return name.get("en-US", next(iter(name.values()), "?")) if isinstance(name, dict) else name


def sri(amo_hash):
    algo, _, hexdigest = amo_hash.partition(":")
    if algo != "sha256":
        raise ValueError(f"unexpected AMO hash {amo_hash}")
    return "sha256-" + base64.b64encode(bytes.fromhex(hexdigest)).decode()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--file", default="home/firefox.nix")
    p.add_argument("--cooldown-days", type=float, default=5)
    p.add_argument("--summary", help="write a Markdown summary here")
    args = p.parse_args()

    cutoff = datetime.datetime.now(datetime.UTC) - datetime.timedelta(
        days=args.cooldown_days
    )
    with open(args.file) as f:
        text = f.read()

    bumps, held = [], []

    def update(m):
        name, block = m.group(1), m.group(2)
        addon_id, pinned = field(block, "addonId"), field(block, "version")
        candidates = newer_versions(addon_id, pinned)
        aged = [
            v
            for v in candidates
            if datetime.datetime.fromisoformat(v["file"]["created"]) <= cutoff
        ]
        if not aged:
            if candidates:
                held.append(f"`{field(block, 'pname')}` {candidates[0]['version']}")
            return m.group(0)
        v = aged[0]
        block = set_field(block, "version", v["version"])
        block = set_field(block, "url", v["file"]["url"])
        block = set_field(block, "hash", sri(v["file"]["hash"]))
        pname = field(block, "pname")
        bumps.append(
            f"- `{pname}`: {pinned} → [{v['version']}]"
            f"(https://addons.mozilla.org/firefox/addon/{urllib.parse.quote(addon_id, safe='')}/versions/)"
            f" (released {v['file']['created'][:10]}, license: {license_name(v)})"
        )
        return f"{name} = firefoxAddon {{\n{block}\n  }};"

    new_text, n = BLOCK.subn(update, text)
    if n == 0:
        sys.exit(f"no firefoxAddon blocks found in {args.file}")
    if new_text != text:
        with open(args.file, "w") as f:
            f.write(new_text)

    summary = []
    if bumps:
        summary += ["Firefox add-on updates from addons.mozilla.org:", "", *bumps]
        summary += [
            "",
            "Check that each license still matches the `license` in "
            "`home/firefox.nix` and that no new permissions are surprising.",
        ]
    if held:
        summary += [
            "",
            f"Newer but younger than {args.cooldown_days:g} days, held back: "
            + ", ".join(held),
        ]
    out = "\n".join(summary) or "No add-on updates."
    print(out)
    if args.summary:
        with open(args.summary, "w") as f:
            f.write(out + "\n")


if __name__ == "__main__":
    main()
