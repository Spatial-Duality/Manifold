#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/.build/self-improvement"
REPORT_PATH="$REPORT_DIR/manifold-self-improvement-report.txt"

mkdir -p "$REPORT_DIR"

{
  echo "Manifold synthetic MCP/UI self-improvement loop"
  echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo

  echo "==> Swift package synthetic MCP contract"
  swift test --filter 'StandingAccessTests/syntheticMCPUIContractReport'
  echo

  echo "==> Synthetic UI suite"
  bash "$ROOT_DIR/script/run_ui_tests.sh" --suite synthetic --derived-data "$ROOT_DIR/.deriveddata-synthetic-ui"
  echo

  echo "Completed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} 2>&1 | tee "$REPORT_PATH"
