#!/usr/bin/env bash
# Start a release: tag the newest commit on main as vX.Y.Z and push the tag. The tag is the release.
#
#   scripts/tag-release.sh 0.11.0           # show the notes, ask, then tag origin/main and push
#   scripts/tag-release.sh 0.11.0 --edit    # edit the notes in $EDITOR first
#   scripts/tag-release.sh 0.11.0 --dry-run # show what would be tagged, change nothing
#   scripts/tag-release.sh --check-tag v0.11.0   # CI: the tag is well-formed, annotated and on main
#   scripts/tag-release.sh --self-test
#
# The version exists only in the tag: release.yml stamps it into the app, the Safari extension and the
# Chrome/Firefox zips at build time, so nothing in the repository has to be bumped. The tag message holds the
# release notes (scripts/release-notes.py: the pull request titles merged since the last tag); the GitHub release
# and Sparkle's update window both show them. See docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }
valid() { [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
# True when $1 is a strictly newer version than $2 (both X.Y.Z).
newer() {
  local a b i
  IFS=. read -ra a <<<"$1"; IFS=. read -ra b <<<"$2"
  for i in 0 1 2; do
    (( 10#${a[i]} > 10#${b[i]} )) && return 0
    (( 10#${a[i]} < 10#${b[i]} )) && return 1
  done
  return 1
}
# Drops <!-- … --> blocks and the blank lines at the start and end.
strip_guide() { python3 -c 'import re,sys; print(re.sub(r"<!--.*?-->", "", sys.stdin.read(), flags=re.S).strip())'; }
latest_tag() { git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1; }

self_test() {
  local ok=0
  check() { if "$@"; then echo "PASS: $*"; else echo "FAIL: $*"; ok=1; fi; }
  refute() { if "$@"; then echo "FAIL: not $*"; ok=1; else echo "PASS: not $*"; fi; }
  check valid 0.11.0
  check valid 10.0.12
  refute valid v0.11.0
  refute valid 0.11
  refute valid 0.11.0-beta.1
  check newer 0.11.0 0.10.0
  check newer 0.10.1 0.10.0
  check newer 1.0.0 0.99.99
  check newer 0.10.0 0.9.9
  refute newer 0.10.0 0.10.0
  refute newer 0.9.10 0.10.0
  check newer 0.08.1 0.8.0
  check [ "$(printf '<!-- guide\n  more -->\n\n## Highlights\n\n- x\n' | strip_guide)" = "$(printf '## Highlights\n\n- x')" ]
  return $ok
}

check_tag() {
  local tag=$1
  [[ $tag == v* ]] && valid "${tag#v}" || die "$tag is not a vX.Y.Z tag"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "no tag $tag"
  # Releases before v0.11.0 were lightweight release-please tags; rebuilding one writes its notes from the log.
  [[ $(git cat-file -t "refs/tags/$tag") == tag ]] ||
    echo "::warning::$tag is not an annotated tag, so it carries no release notes; they are written from the log"
  git fetch -q --no-tags origin main
  git merge-base --is-ancestor "refs/tags/$tag^{commit}" origin/main || die "$tag points at a commit that is not on main"
  echo "$tag is on main"
}

case ${1:-} in
  --self-test) self_test; exit ;;
  --check-tag) check_tag "${2:?usage: tag-release.sh --check-tag vX.Y.Z}"; exit ;;
  ""|-*) echo "usage: scripts/tag-release.sh X.Y.Z [--edit] [--dry-run] | --check-tag vX.Y.Z | --self-test" >&2; exit 64 ;;
esac

VERSION=$1; shift
EDIT=0; DRY=0
for arg in "$@"; do
  case $arg in --edit) EDIT=1 ;; --dry-run) DRY=1 ;; *) die "unknown option $arg" ;; esac
done
valid "$VERSION" || die "version must look like 1.2.3 (no v)"
TAG=v$VERSION

echo "== Fetch main and tags"
git fetch -q --tags origin main
TARGET=$(git rev-parse origin/main)
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "$TAG already exists"
PREV=$(latest_tag)
[[ -n $PREV ]] || die "no earlier vX.Y.Z tag to write notes from"
newer "$VERSION" "${PREV#v}" || die "$VERSION is not newer than the last release, $PREV"
[[ $(git rev-list --count "$PREV..$TARGET") -gt 0 ]] || die "main has nothing new since $PREV"

# The release workflow runs CI again before it builds, but a red or unfinished main is better caught here.
echo "== CI on main $(git rev-parse --short "$TARGET")"
CI=$(gh run list --workflow CI --event push --commit "$TARGET" --limit 1 --json status,conclusion \
  --jq '.[0] | if . == null then "none" elif .status != "completed" then "running" else .conclusion end')
case $CI in
  success) echo "CI passed" ;;
  running) die "CI is still running on main; tag once it passes" ;;
  none) die "no CI run for main's newest commit yet; wait for it" ;;
  *) die "CI on main ended with '$CI'; fix main first" ;;
esac

NOTES=$(mktemp -t triwarden-notes)
trap 'rm -f "$NOTES" "$NOTES.edit"' EXIT
python3 scripts/release-notes.py markdown "$PREV" "$TARGET" >"$NOTES"
if [[ $EDIT == 1 ]]; then
  # A writing guide above the PR titles; strip_guide removes it (and any other <!-- … --> block) afterwards.
  { cat <<'GUIDE'
<!-- Release notes for people using Triwarden: the update window and the top of the GitHub release show them.
  Below are the pull request titles since the last release. Rewrite them as what someone can now do or will
  notice, in plain sentences, most important first. Bold the opening words of each point:

    ## Highlights

    - **Sign up anywhere, not just in Safari.** The password generator now appears on sign-up forms in
      Chrome, Firefox, Edge and Zen too.

    ## Fixes

    - **Fill icons sit beside the field**, so long emails and passwords stay readable.

  Leave out release, CI and test changes; GitHub lists every pull request under the notes anyway.
  This block is removed before tagging. -->

GUIDE
    cat "$NOTES"; } >"$NOTES.edit"
  "${EDITOR:-vi}" "$NOTES.edit"
  strip_guide <"$NOTES.edit" >"$NOTES"
  rm -f "$NOTES.edit"
  [[ -n $(tr -d '[:space:]' <"$NOTES") ]] || die "the notes are empty; nothing tagged"
fi

echo
echo "Triwarden $VERSION, since $PREV ($(git rev-list --count "$PREV..$TARGET") commits on main):"
echo
cat "$NOTES"
echo
if [[ $DRY == 1 ]]; then
  echo "Dry run: would tag $(git rev-parse --short "$TARGET") as $TAG and push it."
  exit 0
fi
read -r -p "Tag $(git log -1 --format='%h %s' "$TARGET") as $TAG and push? [y/N] " answer
[[ $answer == [yY]* ]] || { echo "Nothing tagged."; exit 1; }

# verbatim: the notes' "### Features" headings would otherwise be stripped as comments.
{ printf 'Triwarden %s\n\n' "$VERSION"; cat "$NOTES"; } | git tag -a --cleanup=verbatim -F - "$TAG" "$TARGET"
git push origin "refs/tags/$TAG"
echo
echo "Pushed $TAG. The Release workflow builds, notarizes and publishes it:"
echo "  gh run list --workflow Release --limit 1"
