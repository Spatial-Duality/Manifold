#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# Generate the single-item Sparkle appcast for a signed Manifold disk image.
#
# Usage:
#   bash scripts/generate_appcast.sh <path/to/Manifold-vX.Y.Z.dmg> [sparkle-ed-signature-or-fragment] [output.xml]
#
# If the signature is omitted, this script uses Sparkle's `sign_update` tool.
# It reads the private key from the macOS Keychain by default. To sign from an
# exported key, set MANIFOLD_SPARKLE_ED_KEY_FILE to a private-key file path or
# MANIFOLD_SPARKLE_ED_PRIVATE_KEY to the private key contents.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:-}"
SPARKLE_SIGNATURE="${2:-}"
OUTPUT="${3:-$PROJECT_DIR/ManifoldApp/build/appcast.xml}"

if [[ -z "$DMG_PATH" ]]; then
    echo "usage: $0 <path/to/Manifold-vX.Y.Z.dmg> [sparkle-ed-signature-or-fragment] [output.xml]" >&2
    exit 2
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: disk image not found at $DMG_PATH" >&2
    exit 1
fi

find_sign_update() {
    local candidate
    for candidate in \
        "$PROJECT_DIR/.deriveddata-release/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
        "$PROJECT_DIR/.deriveddata-release/SourcePackages/checkouts/Sparkle/bin/sign_update" \
        "/tmp/manifold-release-derived-data/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
        "/tmp/manifold-release-derived-data/SourcePackages/checkouts/Sparkle/bin/sign_update" \
        "$HOME/Library/Developer/Xcode/DerivedData"/Manifold-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
        "$HOME/Library/Developer/Xcode/DerivedData"/Manifold-*/SourcePackages/checkouts/Sparkle/bin/sign_update \
        "/tmp/manifold-derived-data/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
        "/tmp/manifold-derived-data/SourcePackages/checkouts/Sparkle/bin/sign_update"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

extract_signature() {
    local fragment="$1"
    if [[ "$fragment" == *"sparkle:edSignature="* ]]; then
        sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$fragment"
    else
        printf '%s\n' "$fragment"
    fi
}

sign_update_archive() {
    local sign_update="$1"
    if [[ -n "${MANIFOLD_SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
        printf '%s' "$MANIFOLD_SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$DMG_PATH"
    elif [[ -n "${MANIFOLD_SPARKLE_ED_KEY_FILE:-}" ]]; then
        "$sign_update" --ed-key-file "$MANIFOLD_SPARKLE_ED_KEY_FILE" "$DMG_PATH"
    else
        "$sign_update" "$DMG_PATH"
    fi
}

if [[ -z "$SPARKLE_SIGNATURE" ]]; then
    if ! SIGN_UPDATE="$(find_sign_update)"; then
        echo "error: could not find Sparkle sign_update." >&2
        echo "       Build or resolve the app once, then retry." >&2
        exit 1
    fi
    SIGNATURE_FRAGMENT="$(sign_update_archive "$SIGN_UPDATE")"
    SPARKLE_SIGNATURE="$(extract_signature "$SIGNATURE_FRAGMENT")"
else
    SPARKLE_SIGNATURE="$(extract_signature "$SPARKLE_SIGNATURE")"
fi

if [[ -z "$SPARKLE_SIGNATURE" ]]; then
    echo "error: could not determine Sparkle EdDSA signature." >&2
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
DOWNLOAD_URL="${MANIFOLD_DMG_URL:-https://github.com/Spatial-Duality/Manifold/releases/download/$RELEASE_TAG/$DMG_NAME}"
RELEASE_NOTES_URL="${MANIFOLD_RELEASE_NOTES_URL:-https://github.com/Spatial-Duality/Manifold/releases/tag/$RELEASE_TAG}"
APPCAST_URL="${MANIFOLD_SPARKLE_FEED_URL:-https://github.com/Spatial-Duality/Manifold/releases/latest/download/appcast.xml}"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Manifold Updates</title>
    <link>$APPCAST_URL</link>
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
