#!/usr/bin/env bash
# Fail when Chrome/Firefox zip inputs change without raising package.json above the
# last *released* extension version (.release-please-manifest.json).
#
# Compare against the released anchor — not the PR base tip — so long-lived PRs /
# Debug smoke bumps cannot inflate past the next store version (e.g. 0.4.1 → 0.4.15).
set -euo pipefail
base=${1:?usage: check-extension-version.sh <base-sha>}
pkg=BrowserExtension/WebExtension/package.json
manifest=.release-please-manifest.json
key=BrowserExtension/WebExtension

[[ -f $pkg ]] || { echo "missing $pkg" >&2; exit 1; }
git cat-file -e "$base:$pkg" 2>/dev/null || {
  echo "Base commit has no $pkg; treating as first introduction (ok)."
  exit 0
}

if [[ ! -f $manifest ]]; then
  echo "missing $manifest; falling back to base tip package.json" >&2
  released_ver=$(git show "$base:$pkg" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
else
  released_ver=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$manifest" "$key")
fi

head_ver=$(python3 -c 'import json; print(json.load(open("'"$pkg"'"))["version"])')
base_tip_ver=$(git show "$base:$pkg" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')

python3 - "$released_ver" "$head_ver" "$base_tip_ver" <<'PY'
import sys

def parts(v: str) -> tuple[int, ...]:
    try:
        return tuple(int(p) for p in v.split("."))
    except ValueError as e:
        raise SystemExit(f"invalid semver {v!r}: {e}") from e

released, head, base_tip = sys.argv[1], sys.argv[2], sys.argv[3]
if parts(head) <= parts(released):
    print(
        f"BrowserExtension/WebExtension zip inputs changed, but package.json "
        f"{head} is not greater than last released {released}.",
        file=sys.stderr,
    )
    print(
        "Bump BrowserExtension/WebExtension/package.json above the released "
        "version in .release-please-manifest.json (next store version, e.g. "
        f"{released} → patch+1). Do not stack Debug smoke bumps past that.",
        file=sys.stderr,
    )
    raise SystemExit(1)

note = ""
if parts(base_tip) > parts(released) and parts(head) < parts(base_tip):
    note = f" (base tip was inflated {base_tip}; resetting toward next release is OK)"
print(f"Extension version released {released} → {head}{note} (base tip {base_tip})")
PY
