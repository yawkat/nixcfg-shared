"""What a flake.lock change brings in, by source, for review-deploy.

lock-sources OLD NEW: the inputs are compared by their path from the root
(nixcfg-shared/nixpkgs), transitive ones included. A new revision of the same
source is listed; a changed source (another owner, repository or URL) or a new
input is a warning, since that is how an input would be swapped for a fork.
Nothing is fetched or evaluated. Exits 1 when there is a warning.
"""
import json
import sys


def inputs_by_path(lock):
    nodes = lock["nodes"]
    found = {}

    def visit(name, path, seen):
        for input_name, ref in nodes[name].get("inputs", {}).items():
            if isinstance(ref, list):
                # follows: another input's node, reached by its own path
                continue
            input_path = path + [input_name]
            found["/".join(input_path)] = nodes[ref].get("locked", {})
            if ref not in seen:
                visit(ref, input_path, seen | {ref})

    visit(lock["root"], [], {lock["root"]})
    return found


def source(locked):
    return tuple(locked.get(k) for k in ("type", "owner", "repo", "url", "host", "dir", "path"))


def describe(locked):
    if locked.get("owner"):
        return f"{locked.get('type')}:{locked['owner']}/{locked.get('repo')}"
    return f"{locked.get('type')}:{locked.get('url') or locked.get('path')}"


def main():
    with open(sys.argv[1]) as f:
        old = inputs_by_path(json.load(f))
    with open(sys.argv[2]) as f:
        new = inputs_by_path(json.load(f))

    warnings = []
    for path in sorted(set(old) | set(new)):
        if path not in new:
            print(f"removed  {path} ({describe(old[path])})")
        elif path not in old:
            warnings.append(f"new input {path}: {describe(new[path])}")
        elif source(old[path]) != source(new[path]):
            warnings.append(f"source changed {path}: {describe(old[path])} -> {describe(new[path])}")
        elif old[path].get("narHash") != new[path].get("narHash"):
            old_rev = old[path].get("rev", "?")[:12]
            new_rev = new[path].get("rev", "?")[:12]
            print(f"updated  {path} ({describe(new[path])}) {old_rev} -> {new_rev}")

    for warning in warnings:
        print(f"!!! {warning}")
    sys.exit(1 if warnings else 0)


if __name__ == "__main__":
    main()
