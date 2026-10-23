#!/usr/bin/env bash
# Builds "Highlight Code.app" (universal: Apple Silicon + Intel) and a zip for release.
#
# Usage: scripts/build-app.sh [version]      e.g. scripts/build-app.sh 1.0.0
# Output: build/Highlight Code.app and build/HighlightCode-<version>.zip
#
# Optional environment:
#   SIGN_IDENTITY            code-signing identity (see scripts/import-signing-cert.sh);
#                            defaults to ad-hoc signing ("-")
#   SPARKLE_ED_PRIVATE_KEY   update-signing key; when set, its public half is embedded so
#                            the app can verify and install updates (see setup-signing.sh)
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

echo "==> Embedding Sparkle"
SPARKLE="$(find .build/artifacts -type d -path '*macos-arm64_x86_64/Sparkle.framework' -prune | head -n1)"
if [[ -z "$SPARKLE" ]]; then
  echo "Sparkle.framework not found under .build/artifacts" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/HighlightCode" 2>/dev/null || true

echo "==> Assembling bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"
cp Resources/highlight.js Resources/highlight.js-LICENSE "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(scripts/sparkle-key.sh public)" "$APP/Contents/Info.plist"
  echo "Embedded the update-signing public key: automatic updates enabled"
else
  echo "No SPARKLE_ED_PRIVATE_KEY: automatic updates disabled in this build"
fi

echo "==> Building icon"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "==> Signing with ${SIGN_IDENTITY/#-/an ad-hoc signature} (the app is not notarized)"
# Sparkle's helpers first, then the app; --deep alone can miss nested XPC services.
find "$APP/Contents/Frameworks/Sparkle.framework" \( -name '*.xpc' -o -name '*.app' \) -prune -print0 \
  | xargs -0 -I{} codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "{}"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --requirements - "$APP" 2>/dev/null | sed -n 's/^designated => /Designated requirement: /p'

echo "==> Zipping"
ZIP="$BUILD/HighlightCode-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Built $APP"
echo "Built $ZIP"
