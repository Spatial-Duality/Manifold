#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata-ui-tests"
DESTINATION="platform=macOS,arch=arm64"
SUITE="all"
RESULT_BUNDLE_PATH=""

ONLY_TESTING=()
SKIP_TESTING=("ManifoldAppTests")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --derived-data)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    --only-testing)
      ONLY_TESTING+=("$2")
      shift 2
      ;;
    --skip-testing)
      SKIP_TESTING+=("$2")
      shift 2
      ;;
    --suite)
      SUITE="$2"
      shift 2
      ;;
    --result-bundle-path)
      RESULT_BUNDLE_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if (( ${#ONLY_TESTING[@]} == 0 )); then
  case "$SUITE" in
    fixture)
      ONLY_TESTING+=("ManifoldAppUITests/ManifoldFixtureUITests")
      ;;
    synthetic)
      ONLY_TESTING+=("ManifoldAppUITests/ManifoldSyntheticMCPUITests")
      ONLY_TESTING+=("ManifoldAppUITests/ManifoldSharingMCPUITests")
      ;;
    runtime)
      ONLY_TESTING+=("ManifoldAppUITests/ManifoldSyntheticMCPUITests")
      ONLY_TESTING+=("ManifoldAppUITests/ManifoldSharingMCPUITests")
      ;;
    all)
      ;;
    *)
      echo "Unknown suite: $SUITE" >&2
      exit 64
      ;;
  esac
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/swiftpm-module-cache}"

mkdir -p "$DERIVED_DATA_PATH"
rm -rf \
  "$DERIVED_DATA_PATH/Build/Products/Debug/Manifold.app" \
  "$DERIVED_DATA_PATH/Build/Products/Debug/ManifoldAppUITests-Runner.app"

echo "==> Build for testing"
xcodebuild \
  -project "$ROOT_DIR/Manifold.xcodeproj" \
  -scheme ManifoldUITests \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build-for-testing \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Manifold.app"
RUNNER_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/ManifoldAppUITests-Runner.app"
XCTESTRUN_PATH="$(find "$DERIVED_DATA_PATH/Build/Products" -name '*.xctestrun' -print | head -n 1)"

if [[ ! -d "$APP_PATH" || ! -d "$RUNNER_PATH" || -z "$XCTESTRUN_PATH" ]]; then
  echo "Expected UI test products were not generated." >&2
  exit 1
fi

echo "==> Re-sign app and UI runner for local execution"
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$APP_PATH" "$RUNNER_PATH" 2>/dev/null || true
fi

while IFS= read -r -d '' test_bundle; do
  codesign --force --deep -s - "$test_bundle"
done < <(find "$RUNNER_PATH" -name '*.xctest' -print0)

codesign --force --deep -s - "$APP_PATH"
codesign --force --deep -s - "$RUNNER_PATH"
codesign --verify --deep --strict "$APP_PATH"
codesign --verify --deep --strict "$RUNNER_PATH"

TEST_ARGS=(
  test-without-building
  -xctestrun "$XCTESTRUN_PATH"
  -destination "$DESTINATION"
)

if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
  TEST_ARGS+=("-resultBundlePath" "$RESULT_BUNDLE_PATH")
fi

if (( ${#SKIP_TESTING[@]} > 0 )); then
  for test_id in "${SKIP_TESTING[@]}"; do
    TEST_ARGS+=("-skip-testing:$test_id")
  done
fi

if (( ${#ONLY_TESTING[@]} > 0 )); then
  for test_id in "${ONLY_TESTING[@]}"; do
    TEST_ARGS+=("-only-testing:$test_id")
  done
fi

echo "==> Execute UI tests"
xcodebuild "${TEST_ARGS[@]}"
