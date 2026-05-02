#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${MANIFOLD_VERSION:-$(awk -F: '
    /^[[:space:]]*MARKETING_VERSION[[:space:]]*:/ {
        value = $2
        gsub(/[[:space:]"]/, "", value)
        print value
        exit
    }
' project.yml)}"
if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

CONFIG="${1:-debug}"

APP_IDENTITY="${MANIFOLD_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${MANIFOLD_NOTARY_PROFILE:-}"
REQUIRE_SIGNED_RELEASE="${MANIFOLD_REQUIRE_SIGNED_RELEASE:-0}"
REQUIRE_NOTARIZATION="${MANIFOLD_REQUIRE_NOTARIZATION:-0}"
REQUIRE_SPARKLE="${MANIFOLD_REQUIRE_SPARKLE:-$REQUIRE_SIGNED_RELEASE}"
SPARKLE_FEED_URL="${MANIFOLD_SPARKLE_FEED_URL:-https://spatialduality.com/updates/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${MANIFOLD_SPARKLE_PUBLIC_ED_KEY:-}"

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
    if [[ "$REQUIRE_SPARKLE" == "1" ]]; then
        if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
            echo "error: MANIFOLD_SPARKLE_PUBLIC_ED_KEY is required for official release builds." >&2
            exit 1
        fi
        if [[ -z "$SPARKLE_FEED_URL" ]]; then
            echo "error: MANIFOLD_SPARKLE_FEED_URL is required for official release builds." >&2
            exit 1
        fi
    fi
else
    SWIFT_BUILD_CONFIG="debug"
    XCODE_CONFIGURATION="Debug"
fi

DERIVED_DATA_PATH="$PROJECT_DIR/.deriveddata-release"
XCODE_APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$XCODE_CONFIGURATION/Manifold.app"
BUILD_OUTPUT_DIR="$PROJECT_DIR/ManifoldApp/build"

XCODE_BUILD_ARGS=(
    -project Manifold.xcodeproj
    -scheme Manifold
    -configuration "$XCODE_CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    build
    CODE_SIGNING_ALLOWED=NO
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)

if [[ "$CONFIG" == "release" ]]; then
    XCODE_BUILD_ARGS+=(INFOPLIST_KEY_SUEnableAutomaticChecks=NO)
    if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
        XCODE_BUILD_ARGS+=(
            INFOPLIST_KEY_SUFeedURL="$SPARKLE_FEED_URL"
            INFOPLIST_KEY_SUPublicEDKey="$SPARKLE_PUBLIC_ED_KEY"
        )
    fi
fi

xcodebuild "${XCODE_BUILD_ARGS[@]}" >/tmp/manifold-build-script-xcodebuild.log 2>&1

swift build -c "$SWIFT_BUILD_CONFIG" --product manifold-mcp
BUILD_DIR="$PROJECT_DIR/.build/$SWIFT_BUILD_CONFIG"
MCP_BINARY="$BUILD_DIR/manifold-mcp"

BUNDLE="$BUILD_OUTPUT_DIR/Manifold.app"
MCP_BINARY_PATH="$BUNDLE/Contents/Resources/manifold-mcp"

if [[ ! -d "$XCODE_APP_BUNDLE" ]]; then
    echo "error: expected app bundle at $XCODE_APP_BUNDLE" >&2
    exit 1
fi

mkdir -p "$BUILD_OUTPUT_DIR"
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
        if [[ -d "$BUNDLE/Contents/Frameworks" ]]; then
            while IFS= read -r -d '' nested_code; do
                /usr/bin/codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp --generate-entitlement-der "$nested_code"
            done < <(find "$BUNDLE/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0)
        fi
        /usr/bin/codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp --generate-entitlement-der "$MCP_BINARY_PATH"
        /usr/bin/codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp --generate-entitlement-der "$AGENT_BINARY_PATH"
        /usr/bin/codesign \
            --force \
            --sign "$APP_IDENTITY" \
            --entitlements "$PROJECT_DIR/ManifoldApp/ManifoldApp/Manifold.entitlements" \
            --options runtime \
            --timestamp \
            "$BUNDLE"
        /usr/bin/codesign --verify --deep --strict "$BUNDLE"
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
        echo "Submitting app bundle for notarization..."
        NOTARY_ZIP="$BUILD_OUTPUT_DIR/Manifold-v$VERSION-app-notary.zip"
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
    DMG="$BUILD_OUTPUT_DIR/Manifold-v$VERSION.dmg"
    rm -f "$DMG"
    hdiutil create \
        -volname "Manifold" \
        -srcfolder "$BUNDLE" \
        -ov \
        -format UDZO \
        "$DMG"
    if [[ -n "$APP_IDENTITY" ]]; then
        /usr/bin/codesign --force --sign "$APP_IDENTITY" --timestamp "$DMG"
        /usr/bin/codesign --verify --strict "$DMG"
    fi
    if [[ -n "$NOTARY_PROFILE" ]]; then
        echo "Submitting disk image for notarization..."
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
    LATEST_DMG="$BUILD_OUTPUT_DIR/Manifold.dmg"
    cp "$DMG" "$LATEST_DMG"
    echo "Release disk image: $DMG"
    echo "Stable download copy: $LATEST_DMG"
fi
