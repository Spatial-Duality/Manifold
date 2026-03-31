#!/bin/bash
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES=(
    "$APP_DIR/ManifoldApp/ManifoldApp.swift"
    "$APP_DIR/ManifoldApp/ContentView.swift"
    "$APP_DIR/ManifoldApp/Models/AppState.swift"
    "$APP_DIR/ManifoldApp/Views/SourcesView.swift"
    "$APP_DIR/ManifoldApp/Views/ActivityView.swift"
    "$APP_DIR/ManifoldApp/Views/ProfilesView.swift"
    "$APP_DIR/ManifoldApp/Views/MenuBarView.swift"
)

BUNDLE="$APP_DIR/build/ManifoldApp.app"
mkdir -p "$BUNDLE/Contents/MacOS"

echo "Building Manifold..."
swiftc \
    -o "$BUNDLE/Contents/MacOS/ManifoldApp" \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macosx14.0 \
    -swift-version 6 \
    -parse-as-library \
    "${SOURCES[@]}"

echo "Build complete: $BUNDLE"
echo "Run: open $BUNDLE"
