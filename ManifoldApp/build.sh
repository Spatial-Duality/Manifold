#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION=$(cat VERSION | tr -d '[:space:]')
CONFIG="${1:-debug}"

echo "Building Manifold v$VERSION ($CONFIG)..."

if [ "$CONFIG" = "release" ]; then
    swift build -c release --product ManifoldApp --product manifold-mcp
    BUILD_DIR="$PROJECT_DIR/.build/release"
else
    swift build --product ManifoldApp --product manifold-mcp
    BUILD_DIR="$PROJECT_DIR/.build/debug"
fi

BINARY="$BUILD_DIR/ManifoldApp"
MCP_BINARY="$BUILD_DIR/manifold-mcp"
BUNDLE="$PROJECT_DIR/ManifoldApp/build/Manifold.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/ManifoldApp"
cp "$MCP_BINARY" "$BUNDLE/Contents/Resources/manifold-mcp"
chmod +x "$BUNDLE/Contents/Resources/manifold-mcp"

cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ManifoldApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.spatialduality.manifold</string>
    <key>CFBundleName</key>
    <string>Manifold</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo "Build complete: $BUNDLE (v$VERSION)"
echo "Run: open \"$BUNDLE\""

# If release, also create a zip for GitHub Release
if [ "$CONFIG" = "release" ]; then
    ZIP="$PROJECT_DIR/ManifoldApp/build/Manifold-v$VERSION-macOS.zip"
    cd "$PROJECT_DIR/ManifoldApp/build"
    ditto -c -k --sequesterRsrc --keepParent "Manifold.app" "Manifold-v$VERSION-macOS.zip"
    echo "Release archive: $ZIP"
fi
