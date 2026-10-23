#!/usr/bin/env bash
# Installs the latest Highlight Code release.
#
#   curl -fsSL https://raw.githubusercontent.com/haramrit09k/highlight-code/main/install.sh | bash
#
# The app is open source but not notarized by Apple, so this script clears the download
# quarantine flag itself; that is what lets macOS open it without the Gatekeeper prompt.
set -euo pipefail

REPO="haramrit09k/highlight-code"
APP_NAME="Highlight Code.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Highlight Code runs on macOS only." >&2
  exit 1
fi

echo "Finding the latest release…"
ZIP_URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')"
if [[ -z "$ZIP_URL" ]]; then
  echo "Could not find a release to download. See https://github.com/${REPO}/releases" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading ${ZIP_URL##*/}…"
curl -fsSL "$ZIP_URL" -o "$TMP/app.zip"
ditto -x -k "$TMP/app.zip" "$TMP"

DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

# Quit a running copy before replacing it.
osascript -e 'tell application id "io.github.haramrit09k.highlight-code" to quit' >/dev/null 2>&1 || true
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

# Make the Services menu pick the app up right away instead of after the next login.
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

echo "Installed to $DEST/$APP_NAME"
open "$DEST/$APP_NAME"
