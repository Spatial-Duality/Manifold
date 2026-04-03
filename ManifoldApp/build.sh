#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Building Manifold..."
swift build --product ManifoldApp

BINARY="$PROJECT_DIR/.build/debug/ManifoldApp"
BUNDLE="$PROJECT_DIR/ManifoldApp/build/ManifoldApp.app"
mkdir -p "$BUNDLE/Contents/MacOS"

cp "$BINARY" "$BUNDLE/Contents/MacOS/ManifoldApp"

cat > "$BUNDLE/Contents/Info.plist" << 'PLIST'
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
    <string>0.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Build complete: $BUNDLE"
echo "Run: open $BUNDLE"
