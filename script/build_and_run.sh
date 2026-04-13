#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="/tmp/manifold-derived-data"
PROJECT_PATH="$ROOT_DIR/Manifold.xcodeproj"
SCHEME="Manifold"
CONFIGURATION="Debug"
APP_NAME="Manifold"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TELEMETRY_SUBSYSTEM="com.spatialduality.manifold"

build_app() {
  env \
    CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    CODE_SIGNING_ALLOWED=NO
}

stop_running() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "${APP_NAME}Agent" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

log_stream() {
  local predicate="$1"
  /usr/bin/log stream --info --style compact --predicate "$predicate"
}

stop_running
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    log_stream "process == \"$APP_NAME\" OR process == \"${APP_NAME}Agent\""
    ;;
  --telemetry|telemetry)
    open_app
    log_stream "subsystem BEGINSWITH \"$TELEMETRY_SUBSYSTEM\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
