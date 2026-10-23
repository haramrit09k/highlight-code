#!/usr/bin/env bash
# Writes the Sparkle update feed (appcast.xml) for one release. The Release workflow
# attaches it to the GitHub release, and the app reads it from
# https://github.com/<repo>/releases/latest/download/appcast.xml
#
# Usage: scripts/make-appcast.sh <version> <zip>  > appcast.xml
# Needs $SPARKLE_ED_PRIVATE_KEY (see scripts/sparkle-key.sh).
set -euo pipefail

VERSION="${1:?version}"
ZIP="${2:?zip}"
REPO="${GITHUB_REPOSITORY:-haramrit09k/highlight-code}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

LENGTH="$(wc -c < "$ZIP" | tr -d ' ')"
SIGNATURE="$("$ROOT/scripts/sparkle-key.sh" sign "$ZIP")"
URL="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Highlight Code</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF
