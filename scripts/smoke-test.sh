#!/usr/bin/env bash
# End-to-end checks against the built app. Run after scripts/build-app.sh.
#
# Usage: scripts/smoke-test.sh [--install]
#   --install  also copies the app to ~/Applications, registers its services and
#              calls "Highlight Code" through the real macOS Services machinery.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Highlight Code.app"
BIN="$APP/Contents/MacOS/HighlightCode"
OUT="$ROOT/build/smoke"
mkdir -p "$OUT"

echo "==> Command-line mode"
printf 'import os\n\ndef main():\n    print(os.getcwd())  # where am I\n' | "$BIN" --rtf > "$OUT/sample.rtf"
head -c 6 "$OUT/sample.rtf" | grep -q '{\\rtf1' || { echo "FAIL: output is not RTF"; exit 1; }
grep -q 'Menlo' "$OUT/sample.rtf" || { echo "FAIL: RTF does not use Menlo"; exit 1; }
grep -q '\\colortbl' "$OUT/sample.rtf" || { echo "FAIL: RTF has no colours"; exit 1; }
echo "PASS"

echo "==> Snapshots"
"$BIN" --snapshot "$OUT/snapshots"
for name in settings-light settings-dark before-after toolbar; do
  test -s "$OUT/snapshots/$name.png" || { echo "FAIL: missing $name.png"; exit 1; }
done
echo "PASS"

if [[ "${1:-}" == "--install" ]]; then
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
  swift "$ROOT/scripts/perform-service.swift"
fi
