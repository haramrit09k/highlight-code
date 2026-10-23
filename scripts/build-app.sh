#!/usr/bin/env bash
# Builds "Highlight Code.app" (universal: Apple Silicon + Intel) and a zip for release.
#
# Usage: scripts/build-app.sh [version]      e.g. scripts/build-app.sh 1.0.0
# Output: build/Highlight Code.app and build/HighlightCode-<version>.zip
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Highlight Code.app"

cd "$ROOT"
rm -rf "$APP" "$BUILD"/HighlightCode-*.zip "$BUILD/AppIcon.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling"
swift build -c release --arch arm64 --arch x86_64 --product HighlightCode
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_DIR/HighlightCode" "$APP/Contents/MacOS/HighlightCode"

echo "==> Assembling bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"
cp Resources/highlight.js Resources/highlight.js-LICENSE "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"

echo "==> Building icon"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing (ad-hoc; the app is not notarized)"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping"
ZIP="$BUILD/HighlightCode-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Built $APP"
echo "Built $ZIP"
