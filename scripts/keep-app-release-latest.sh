#!/usr/bin/env bash
# After release-please publishes an extension-v* GitHub release, keep Latest on an app release.
#
# release-please always creates the GitHub release as Latest. It has no make_latest
# option (https://github.com/googleapis/release-please/issues/2317). An extension
# release has no appcast.xml, so while it is Latest, Check for Updates 404s on
# /releases/latest/download/appcast.xml.
#
# Setting make_latest=false removes Latest from that release and does not promote
# another one, so this also points Latest at the app release (vX.Y.Z). Pass the
# app tag when this run created one. release-please still marks other app
# releases Latest; this script is only invoked for extension-v*.
#
# Usage: keep-app-release-latest.sh <extension-tag> [app-tag]
#   app-tag  vX.Y.Z created in this same release-please run. When omitted or not an
#            app tag, the newest published vX.Y.Z release is used.
set -euo pipefail

extension_tag=${1:?extension tag required}
app_tag=${2:-}
repo=${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY}

# release-please tags the extension component "extension-v*". Refuse anything else
# so a bad output cannot move Latest off the app.
[[ $extension_tag == extension-v* ]] || {
  echo "refusing to change Latest for unexpected tag: ${extension_tag}" >&2
  exit 1
}

if [[ ! $app_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  app_tag=$(
    gh api --paginate "repos/${repo}/releases?per_page=100" \
      --jq '.[] | select(.draft == false and .prerelease == false and (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))) | [.published_at, .tag_name] | @tsv' \
      | sort | tail -1 | cut -f2
  )
fi

[[ $app_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "no app release (vX.Y.Z) to keep as Latest" >&2
  exit 1
}

# Last write wins. Clear the extension release first, then mark the app release
# Latest so /releases/latest still serves that release's appcast.xml.
gh release edit "$extension_tag" --repo "$repo" --latest=false
gh release edit "$app_tag" --repo "$repo" --latest=true

latest=$(gh release view --repo "$repo" --json tagName --jq .tagName)
echo "Latest is ${latest}; ${extension_tag} is not Latest"
[[ $latest == "$app_tag" ]] || {
  echo "expected Latest to be ${app_tag}, got ${latest}" >&2
  exit 1
}
