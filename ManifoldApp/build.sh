#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Building Manifold..."
swift build --product ManifoldApp

# Create app bundle from the SPM-built binary
BINARY="$PROJECT_DIR/.build/debug/ManifoldApp"
BUNDLE="$PROJECT_DIR/ManifoldApp/build/ManifoldApp.app"
mkdir -p "$BUNDLE/Contents/MacOS"

cp "$BINARY" "$BUNDLE/Contents/MacOS/ManifoldApp"

# Ensure Info.plist exists
if [ ! -f "$BUNDLE/Contents/Info.plist" ]; then
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
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
fi

echo "Build complete: $BUNDLE"
echo "Run: open $BUNDLE"
