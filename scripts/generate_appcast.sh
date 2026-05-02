#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Generate the single-item Sparkle appcast that is published at
# https://spatialduality.com/updates/appcast.xml.
#
# Usage:
#   bash scripts/generate_appcast.sh <path/to/Manifold-vX.Y.Z.dmg> <sparkle-ed-signature> [output.xml]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:-}"
SPARKLE_SIGNATURE="${2:-}"
OUTPUT="${3:-$PROJECT_DIR/website/spatialduality-site/updates/appcast.xml}"

if [[ -z "$DMG_PATH" || -z "$SPARKLE_SIGNATURE" ]]; then
    echo "usage: $0 <path/to/Manifold-vX.Y.Z.dmg> <sparkle-ed-signature> [output.xml]" >&2
    exit 2
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: disk image not found at $DMG_PATH" >&2
    exit 1
fi

VERSION="$(awk -F: '
    /^[[:space:]]*MARKETING_VERSION[[:space:]]*:/ {
        value = $2
        gsub(/[[:space:]"]/, "", value)
        print value
        exit
    }
' "$PROJECT_DIR/project.yml")"
if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

if [[ -n "${MANIFOLD_BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER="$MANIFOLD_BUILD_NUMBER"
elif command -v git >/dev/null 2>&1 && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    BUILD_NUMBER="$(git -C "$PROJECT_DIR" rev-list --count HEAD)"
else
    BUILD_NUMBER="1"
fi

LENGTH="$(stat -f%z "$DMG_PATH")"
RELEASE_TAG="${MANIFOLD_RELEASE_TAG:-v$VERSION}"
DMG_NAME="$(basename "$DMG_PATH")"
DOWNLOAD_URL="${MANIFOLD_DMG_URL:-https://github.com/amargandhi/Manifold/releases/download/$RELEASE_TAG/$DMG_NAME}"
RELEASE_NOTES_URL="${MANIFOLD_RELEASE_NOTES_URL:-https://spatialduality.com/releases/}"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Manifold Updates</title>
    <link>https://spatialduality.com/updates/appcast.xml</link>
    <description>Signed Manifold updates.</description>
    <language>en</language>
    <item>
      <title>Manifold $VERSION</title>
      <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="$DOWNLOAD_URL"
        sparkle:version="$BUILD_NUMBER"
        sparkle:shortVersionString="$VERSION"
        sparkle:edSignature="$SPARKLE_SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

echo "Wrote appcast: $OUTPUT"
