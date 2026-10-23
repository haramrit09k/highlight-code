#!/usr/bin/env bash
# End-to-end checks against the built app. Run after scripts/build-app.sh.
#
# Usage: scripts/smoke-test.sh [--install] [--no-snapshots]
#   --install       also copies the app to ~/Applications, registers its services and
#                   calls "Highlight Code" through the real macOS Services machinery.
#   --no-snapshots  skips rendering the screenshots (they hang on some virtual machines,
#                   e.g. GitHub's macOS 26 Intel runners).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Highlight Code.app"
BIN="$APP/Contents/MacOS/HighlightCode"
OUT="$ROOT/build/smoke"
mkdir -p "$OUT"

echo "==> Disk image"
# Checked with hdiutil, which still works (deprecated, not removed, in macOS 27) and has
# the read-only, no-Finder attach this needs on every macOS version the app supports.
MOUNT="$(mktemp -d)"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$ROOT/build/HighlightCode.dmg" >/dev/null
VOLUME_NAME="$(diskutil info "$MOUNT" 2>/dev/null | sed -n 's/^ *Volume Name: *//p')"
[[ "$VOLUME_NAME" == "Highlight Code" ]] || echo "warning: volume name is '$VOLUME_NAME'"
test -d "$MOUNT/Highlight Code.app" || { echo "FAIL: the app is missing from the disk image"; hdiutil detach "$MOUNT" >/dev/null; exit 1; }
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]] || { echo "FAIL: no Applications shortcut"; hdiutil detach "$MOUNT" >/dev/null; exit 1; }
codesign --verify --deep --strict "$MOUNT/Highlight Code.app" || { echo "FAIL: the app in the disk image fails codesign"; hdiutil detach "$MOUNT" >/dev/null; exit 1; }
hdiutil detach "$MOUNT" >/dev/null
echo "PASS"

echo "==> Command-line mode"
printf 'import os\n\ndef main():\n    print(os.getcwd())  # where am I\n' | "$BIN" --rtf > "$OUT/sample.rtf"
head -c 6 "$OUT/sample.rtf" | grep -q '{\\rtf1' || { echo "FAIL: output is not RTF"; exit 1; }
grep -q 'Menlo' "$OUT/sample.rtf" || { echo "FAIL: RTF does not use Menlo"; exit 1; }
grep -q '\\colortbl' "$OUT/sample.rtf" || { echo "FAIL: RTF has no colours"; exit 1; }
echo "PASS"

INSTALL=false SNAPSHOTS=true
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --no-snapshots) SNAPSHOTS=false ;;
  esac
done

# Runs a command, killing it if it takes longer than $1 seconds (macOS has no `timeout`).
with_timeout() {
  perl -e 'alarm shift; exec @ARGV or die "$!"' "$@"
}

if $SNAPSHOTS; then
echo "==> Snapshots"
with_timeout 180 "$BIN" --snapshot "$OUT/snapshots" || { echo "FAIL: snapshots failed or timed out"; exit 1; }
for name in settings-light settings-dark before-after toolbar; do
  test -s "$OUT/snapshots/$name.png" || { echo "FAIL: missing $name.png"; exit 1; }
done
echo "PASS"
fi

if $INSTALL; then
  echo "==> Services menu integration"
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Highlight Code.app"
  cp -R "$APP" "$HOME/Applications/"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Highlight Code.app"
  /System/Library/CoreServices/pbs -update
  sleep 2
  /System/Library/CoreServices/pbs -dump_pboard 2>/dev/null | grep -q "Highlight Code" \
    && echo "Service is registered with pbs" \
    || echo "warning: service not listed by pbs -dump_pboard"
  with_timeout 300 swift "$ROOT/scripts/perform-service.swift" || { echo "FAIL: service call failed or timed out"; exit 1; }
fi
