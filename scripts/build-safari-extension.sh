#!/usr/bin/env bash
# Build the browser extension for Safari (WXT) and copy it flat into the Safari appex's Resources.
# Run by the TriwardenSafari target's "Build web extension" phase (project.yml).
set -euo pipefail
# Absolute first: the login-shell retry below runs this file again after the cd.
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$self")/../BrowserExtension/WebExtension"

# Xcode runs build phases with a minimal PATH, without mise, nvm or Homebrew's shell setup. If node or pnpm
# isn't visible, run again under the user's interactive login shell, which has the PATH their terminal has (mise and nvm hook in via .zshrc).
if ! command -v node >/dev/null || ! command -v pnpm >/dev/null; then
  if [[ -z "${TRIWARDEN_LOGIN_SHELL:-}" ]]; then
    export TRIWARDEN_LOGIN_SHELL=1
    exec "${SHELL:-/bin/zsh}" -lic 'exec "$0" "$@"' "$self" "$@"
  fi
  echo "error: node and pnpm are required to build the Safari extension (brew install node pnpm)" >&2
  exit 1
fi

# No terminal here: never stop to ask whether to rebuild node_modules.
export CI=true
pnpm install --frozen-lockfile --silent
pnpm exec wxt build -b safari >&2

dest="${1:-}"
if [[ -n "$dest" ]]; then
  mkdir -p "$dest"
  rsync -a .output/safari-mv3/ "$dest/"
fi
