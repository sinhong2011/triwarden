#!/usr/bin/env bash
# Version gate for the extension release-please PR only.
#
# Feature PRs may change Chrome/Firefox zip inputs without bumping
# BrowserExtension/WebExtension/package.json. The store version is raised later
# by the extension release-please PR:
#   branch prefix release-please--branches--main--components--extension
#   titles like chore(extension): release …
# CI runs this script only for that branch, and only when zip inputs changed.
#
# package.json must be greater than the last *released* extension version, which
# is BrowserExtension/WebExtension in .release-please-manifest.json on the PR
# *base* (main). This PR already writes that same version into the working-tree
# manifest, so reading HEAD would compare 0.5.0 to 0.5.0 and fail a correct
# release. Do not use the base tip package.json as the anchor either: that can
# be inflated relative to the last store release.
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

if git cat-file -e "$base:$manifest" 2>/dev/null; then
  released_ver=$(git show "$base:$manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$key")
else
  echo "Base commit has no $manifest; falling back to base tip package.json" >&2
  released_ver=$(git show "$base:$pkg" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
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
        "Extension release-please PR changed BrowserExtension/WebExtension zip "
        f"inputs, but package.json {head} is not greater than last released {released}.",
        file=sys.stderr,
    )
    print(
        "That PR (branch prefix release-please--branches--main--components--extension, "
        "titles like chore(extension): release …) must set "
        "BrowserExtension/WebExtension/package.json above the last released "
        "version in the PR base .release-please-manifest.json (next store version, e.g. "
        f"{released} → patch+1). Feature PRs do not bump package.json.",
        file=sys.stderr,
    )
    raise SystemExit(1)

note = ""
if parts(base_tip) > parts(released) and parts(head) < parts(base_tip):
    note = f" (base tip was inflated {base_tip}; resetting toward next release is OK)"
print(f"Extension version released {released} → {head}{note} (base tip {base_tip})")
PY
