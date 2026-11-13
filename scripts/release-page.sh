#!/usr/bin/env bash
# The GitHub release page for vVERSION, on stdout. scripts/release.sh publishes it; run it by hand to preview one.
#
#   scripts/release-page.sh 0.11.0 notes.md > body.md
#
# Three parts, the way readers use them:
#   1. notes.md: what changed for people using Triwarden (the annotated tag's message, scripts/tag-release.sh).
#      Sparkle's update window shows this part alone.
#   2. GitHub's generated list of every pull request since the previous release, with authors, links and the
#      Full Changelog comparison. Left out, with a warning, when GitHub can't make it (offline, no tag yet).
#   3. How to install or update, where to get the browser extension, and what it needs.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release-page.sh <version> <notes.md>}
NOTES=${2:?usage: scripts/release-page.sh <version> <notes.md>}
REPO=sinhong2011/triwarden
TAG=v$VERSION

cat "$NOTES"
echo

PREV=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$TAG^" 2>/dev/null ||
  git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null || true)
ARGS=(-f "tag_name=$TAG")
[[ -n $PREV && $PREV != "$TAG" ]] && ARGS+=(-f "previous_tag_name=$PREV")
if LIST=$(gh api "repos/$REPO/releases/generate-notes" "${ARGS[@]}" --jq .body 2>/dev/null) && [[ -n $LIST ]]; then
  printf '\n%s\n' "$LIST"
else
  echo "warning: GitHub could not list the pull requests for $TAG; the page has the notes and install text only" >&2
fi

cat <<EOF

---

**Install:** download [Triwarden-$VERSION.dmg](https://github.com/$REPO/releases/download/$TAG/Triwarden-$VERSION.dmg) and drag Triwarden to Applications, or \`brew install --cask sinhong2011/tap/triwarden\`.
**Update:** Triwarden › Check for Updates…, or \`brew upgrade --cask triwarden\`. The Safari extension updates with the app.
**Browser extension:** Safari's comes with the app. Chrome, Edge and Brave: [Chrome Web Store](https://chromewebstore.google.com/detail/triwarden/deiehcliaaoigminkkbnjlgmaoagimdm). Firefox and Zen: [Firefox Add-ons](https://addons.mozilla.org/firefox/addon/triwarden/). Store updates follow review; any \`triwarden-extension-*\` zips below are the files sent to the stores, kept as a record.
Requires macOS 26 (Tahoe) or later. Signed with Developer ID and notarized by Apple.
EOF
