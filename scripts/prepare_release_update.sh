#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="$(awk -F: '
    /^[[:space:]]*MARKETING_VERSION[[:space:]]*:/ {
        value = $2
        gsub(/[[:space:]"]/, "", value)
        print value
        exit
    }
' project.yml)"
if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

if [[ -z "${MANIFOLD_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    echo "error: MANIFOLD_SPARKLE_PUBLIC_ED_KEY is required." >&2
    echo "       Run scripts/sparkle_generate_keys.sh once, then export the public key." >&2
    exit 1
fi

bash ManifoldApp/build.sh release

BUILD_DIR="$PROJECT_DIR/ManifoldApp/build"
APP_PATH="$BUILD_DIR/Manifold.app"
DMG_PATH="$BUILD_DIR/Manifold-v$VERSION.dmg"
APPCAST_PATH="$BUILD_DIR/appcast.xml"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: expected release disk image at $DMG_PATH" >&2
    exit 1
fi

bash scripts/generate_appcast.sh "$DMG_PATH" "${MANIFOLD_SPARKLE_SIGNATURE:-}" "$APPCAST_PATH"
bash scripts/validate_appcast.sh "$APPCAST_PATH" --skip-net

POSTURE_ARGS=(--app "$APP_PATH" --require-sparkle)
if [[ -n "${MANIFOLD_CODESIGN_IDENTITY:-}" ]]; then
    POSTURE_ARGS+=(--require-signed-app)
fi
bash scripts/validate_release_posture.sh "${POSTURE_ARGS[@]}"

echo ""
echo "Release update artifacts:"
echo "  $DMG_PATH"
echo "  $APPCAST_PATH"
