#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="$(tr -d '[:space:]' < VERSION)"
CONFIG="${1:-debug}"

APP_IDENTITY="${MANIFOLD_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${MANIFOLD_NOTARY_PROFILE:-}"
REQUIRE_SIGNED_RELEASE="${MANIFOLD_REQUIRE_SIGNED_RELEASE:-0}"
REQUIRE_NOTARIZATION="${MANIFOLD_REQUIRE_NOTARIZATION:-0}"

# CFBundleVersion must be a strictly increasing integer for Sparkle to deliver
# updates. Derive it from git history so every commit on main bumps it without
# manual intervention. Allow override via $MANIFOLD_BUILD_NUMBER for CI builds
# from a tag where the rev count would be the same as the prior tag's HEAD.
if [[ -n "${MANIFOLD_BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER="$MANIFOLD_BUILD_NUMBER"
elif command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
else
    BUILD_NUMBER="1"
fi

echo "Building Manifold v$VERSION (build $BUILD_NUMBER, $CONFIG)..."

if [[ "$CONFIG" == "release" ]]; then
    SWIFT_BUILD_CONFIG="release"
    XCODE_CONFIGURATION="Release"
else
    SWIFT_BUILD_CONFIG="debug"
    XCODE_CONFIGURATION="Debug"
fi

DERIVED_DATA_PATH="$PROJECT_DIR/.deriveddata-release"
XCODE_APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$XCODE_CONFIGURATION/Manifold.app"

xcodebuild \
    -project Manifold.xcodeproj \
    -scheme Manifold \
    -configuration "$XCODE_CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" >/tmp/manifold-build-script-xcodebuild.log 2>&1

swift build -c "$SWIFT_BUILD_CONFIG" --product manifold-mcp
BUILD_DIR="$PROJECT_DIR/.build/$SWIFT_BUILD_CONFIG"
MCP_BINARY="$BUILD_DIR/manifold-mcp"

BUNDLE="$PROJECT_DIR/ManifoldApp/build/Manifold.app"
MCP_BINARY_PATH="$BUNDLE/Contents/Resources/manifold-mcp"

if [[ ! -d "$XCODE_APP_BUNDLE" ]]; then
    echo "error: expected app bundle at $XCODE_APP_BUNDLE" >&2
    exit 1
fi

rm -rf "$BUNDLE"
ditto "$XCODE_APP_BUNDLE" "$BUNDLE"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$MCP_BINARY" "$MCP_BINARY_PATH"
chmod +x "$MCP_BINARY_PATH"

LAUNCH_AGENT_DIR="$BUNDLE/Contents/Library/LaunchAgents"
LAUNCH_SERVICE_DIR="$BUNDLE/Contents/Library/LaunchServices"
AGENT_BINARY_PATH="$LAUNCH_SERVICE_DIR/ManifoldAgent"

if [[ ! -x "$AGENT_BINARY_PATH" ]]; then
    echo "error: expected bundled ManifoldAgent helper at $AGENT_BINARY_PATH" >&2
    exit 1
fi

if [[ "$CONFIG" == "release" ]]; then
    if [[ "$REQUIRE_SIGNED_RELEASE" == "1" && -z "$APP_IDENTITY" ]]; then
        echo "error: MANIFOLD_CODESIGN_IDENTITY is required for release builds." >&2
        exit 1
    fi

    if [[ -n "$APP_IDENTITY" ]]; then
        echo "Signing nested helpers and app bundle..."
        /usr/bin/codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp "$MCP_BINARY_PATH"
        /usr/bin/codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp "$AGENT_BINARY_PATH"
        /usr/bin/codesign \
            --force \
            --sign "$APP_IDENTITY" \
            --entitlements "$PROJECT_DIR/ManifoldApp/ManifoldApp/Manifold.entitlements" \
            --options runtime \
            --timestamp \
            "$BUNDLE"
    fi

    if [[ "$REQUIRE_NOTARIZATION" == "1" && -z "$NOTARY_PROFILE" ]]; then
        echo "error: MANIFOLD_NOTARY_PROFILE is required for notarized release builds." >&2
        exit 1
    fi

    if [[ -n "$NOTARY_PROFILE" ]]; then
        if [[ -z "$APP_IDENTITY" ]]; then
            echo "error: notarization requires MANIFOLD_CODESIGN_IDENTITY." >&2
            exit 1
        fi
        echo "Submitting app for notarization..."
        NOTARY_ZIP="$PROJECT_DIR/ManifoldApp/build/Manifold-v$VERSION-notary.zip"
        rm -f "$NOTARY_ZIP"
        ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$NOTARY_ZIP"
        xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$BUNDLE"
        rm -f "$NOTARY_ZIP"
    fi
fi

echo "Build complete: $BUNDLE (v$VERSION)"
echo "Run: open \"$BUNDLE\""

if [[ "$CONFIG" == "release" ]]; then
    ZIP="$PROJECT_DIR/ManifoldApp/build/Manifold-v$VERSION-macOS.zip"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ZIP"
    echo "Release archive: $ZIP"
fi
