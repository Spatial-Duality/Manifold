#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/Manifold.xcodeproj/project.pbxproj"

APP_PATH=""
REQUIRE_SIGNED_APP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="${2:-}"
            shift 2
            ;;
        --require-signed-app)
            REQUIRE_SIGNED_APP=1
            shift
            ;;
        *)
            echo "usage: $0 [--app /path/to/Manifold.app] [--require-signed-app]" >&2
            exit 2
            ;;
    esac
done

fail() {
    echo "error: $*" >&2
    exit 1
}

note() {
    echo "[release-check] $*"
}

[[ -f "$PROJECT_FILE" ]] || fail "Missing Xcode project file at $PROJECT_FILE"

grep -q 'ENABLE_HARDENED_RUNTIME = YES;' "$PROJECT_FILE" \
    || fail "Release build settings must enable hardened runtime."
grep -q 'ENABLE_DEBUG_DYLIB = NO;' "$PROJECT_FILE" \
    || fail "Release build settings must disable the debug dylib."
grep -q -- '--options runtime' "$PROJECT_FILE" \
    || fail "Nested helper signing must include --options runtime."

if [[ -n "$APP_PATH" ]]; then
    [[ -d "$APP_PATH" ]] || fail "App bundle not found at $APP_PATH"
    APP_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
    [[ -n "$APP_EXECUTABLE" ]] || fail "CFBundleExecutable is missing from the app Info.plist."
    [[ -x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE" ]] || fail "Main app executable is missing."
    [[ -x "$APP_PATH/Contents/Resources/manifold-mcp" ]] || fail "Bundled manifold-mcp helper is missing."
    [[ -x "$APP_PATH/Contents/Library/LaunchServices/ManifoldAgent" ]] || fail "Bundled ManifoldAgent helper is missing."
    [[ -f "$APP_PATH/Contents/Library/LaunchAgents/com.spatialduality.manifold.runtime.plist" ]] \
        || fail "Launch agent plist is missing from the app bundle."

    if /usr/bin/codesign -dvv "$APP_PATH" >/tmp/manifold-release-codesign.log 2>&1; then
        if /usr/bin/codesign --verify --deep --strict "$APP_PATH" >/tmp/manifold-release-verify.log 2>&1; then
            /usr/bin/codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -q 'Runtime Version=' \
                || fail "Signed app is missing hardened runtime metadata."
            /usr/sbin/spctl -a -vv "$APP_PATH" >/tmp/manifold-release-spctl.log 2>&1 \
                || fail "spctl assessment failed for $APP_PATH"
        elif [[ "$REQUIRE_SIGNED_APP" == "1" ]]; then
            fail "codesign verification failed for $APP_PATH"
        else
            note "App bundle is not distributable-signed; skipping signature and Gatekeeper checks."
        fi
    elif [[ "$REQUIRE_SIGNED_APP" == "1" ]]; then
        fail "Signed app bundle required but $APP_PATH is unsigned."
    else
        note "App bundle is unsigned; skipping artifact signature and Gatekeeper checks."
    fi
fi

note "Release posture validation passed."
