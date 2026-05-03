#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <Manifold.app> <output.dmg> [volume-name]" >&2
    exit 2
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-Manifold}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH" >&2
    exit 1
fi

if [[ -e "/Volumes/$VOLUME_NAME" ]]; then
    echo "error: /Volumes/$VOLUME_NAME is already mounted. Eject it before creating the release DMG." >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="$(basename "$APP_PATH")"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/manifold-dmg.XXXXXX")"
MOUNT_DIR=""
RW_DMG="$TMP_ROOT/template.dmg"
LAYOUT_VOLUME_NAME="$VOLUME_NAME Installer $$"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/swiftpm-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

cleanup() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

APP_SIZE_MB="$(du -sm "$APP_PATH" | awk '{print $1}')"
DMG_SIZE_MB="$((APP_SIZE_MB + 120))"

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"

hdiutil create \
    -size "${DMG_SIZE_MB}m" \
    -fs HFS+ \
    -volname "$LAYOUT_VOLUME_NAME" \
    -quiet \
    "$RW_DMG"

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"

if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "error: could not find mounted DMG volume in hdiutil output:" >&2
    echo "$ATTACH_OUTPUT" >&2
    exit 1
fi

ditto "$APP_PATH" "$MOUNT_DIR/$APP_NAME"
ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"

ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ ! -f "$ICON_PATH" ]]; then
    echo "error: app icon not found at $ICON_PATH" >&2
    exit 1
fi

swift "$PROJECT_DIR/scripts/render_dmg_background.swift" "$MOUNT_DIR/.background/background.png" "$ICON_PATH"
chflags hidden "$MOUNT_DIR/.background"

if ! /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  set theDisk to (POSIX file "$MOUNT_DIR") as alias
  set backgroundImage to (POSIX file "$MOUNT_DIR/.background/background.png") as alias
  open theDisk
  delay 1
  set containerWindow to container window of theDisk
  set current view of containerWindow to icon view
  set toolbar visible of containerWindow to false
  set statusbar visible of containerWindow to false
  set bounds of containerWindow to {120, 120, 780, 540}
  set viewOptions to the icon view options of containerWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 104
  set text size of viewOptions to 13
  set background picture of viewOptions to backgroundImage
  set position of item "$APP_NAME" of theDisk to {190, 285}
  try
    set position of item "Applications" of theDisk to {470, 285}
  end try
  update theDisk without registering applications
  delay 1
  close containerWindow
end tell
APPLESCRIPT
then
    echo "warning: Finder DMG layout failed; continuing with an unstyled disk image." >&2
fi

sync
sleep 2
diskutil rename "$MOUNT_DIR" "$VOLUME_NAME" >/dev/null
MOUNT_DIR="/Volumes/$VOLUME_NAME"

for attempt in 1 2 3 4 5; do
    if hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1; then
        break
    fi
    sleep "$attempt"
done

if mount | grep -F " on $MOUNT_DIR " >/dev/null 2>&1; then
    hdiutil detach "$MOUNT_DIR" -force -quiet
fi

hdiutil convert \
    "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    -o "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG" -quiet
