#!/usr/bin/env bash
# Version gate for the app release-please PR only.
#
# Feature PRs may change Chrome/Firefox zip inputs without bumping
# BrowserExtension/WebExtension/package.json. The store version is raised on
# the app release PR (branch prefix release-please--, titles like
# chore: release …), in lockstep with MARKETING_VERSION. CI runs this script
# only for that branch, and only when zip inputs changed.
#
# package.json must match project.yml MARKETING_VERSION and be greater than
# the version on the PR base (the last zip that could have been submitted).
# .release-please-manifest.json must be valid JSON so a conflicted release
# commit cannot land.
set -euo pipefail
base=${1:?usage: check-extension-version.sh <base-sha>}
pkg=BrowserExtension/WebExtension/package.json
manifest=.release-please-manifest.json
project=project.yml

[[ -f $pkg ]] || { echo "missing $pkg" >&2; exit 1; }
[[ -f $project ]] || { echo "missing $project" >&2; exit 1; }
git cat-file -e "$base:$pkg" 2>/dev/null || {
  echo "Base commit has no $pkg; treating as first introduction (ok)."
  exit 0
}

python3 - "$base" "$pkg" "$manifest" "$project" <<'PY'
import json, re, subprocess, sys

base, pkg, manifest, project = sys.argv[1:]


def parts(v: str) -> tuple[int, ...]:
    try:
        return tuple(int(p) for p in v.split("."))
    except ValueError as e:
        raise SystemExit(f"invalid semver {v!r}: {e}") from e


def load_json(path: str):
    try:
        with open(path) as fh:
            return json.load(fh)
    except json.JSONDecodeError as e:
        raise SystemExit(f"{path} is not valid JSON: {e}") from e


def git_show_json(sha: str, path: str):
    raw = subprocess.check_output(["git", "show", f"{sha}:{path}"], text=True)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise SystemExit(f"{sha}:{path} is not valid JSON: {e}") from e


def marketing_version(path: str) -> str:
    text = open(path).read()
    match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
    if not match:
        raise SystemExit(f"{path} has no MARKETING_VERSION")
    return match.group(1)


load_json(manifest)
head_ver = str(load_json(pkg)["version"])
app_ver = marketing_version(project)
base_ver = str(git_show_json(base, pkg)["version"])

if head_ver != app_ver:
    raise SystemExit(
        f"{pkg} is {head_ver}, but {project} MARKETING_VERSION is {app_ver}. "
        "The app release PR must set them to the same version."
    )

if parts(head_ver) <= parts(base_ver):
    raise SystemExit(
        f"{pkg} {head_ver} is not greater than the PR base {base_ver}. "
        "Chrome/Firefox need a new store version on each app release that "
        "touches zip inputs. Feature PRs do not bump package.json."
    )

print(f"Extension store version {base_ver} → {head_ver} (app {app_ver})")
PY
