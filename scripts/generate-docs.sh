#!/usr/bin/env bash
# Copyright 2026 Spatial Duality
# SPDX-License-Identifier: Apache-2.0
#
# generate-docs.sh — build DocC documentation for the Swift packages.
#
# Outputs to ./docs (transformed for static hosting on GitHub Pages or
# any static file server). Run from the repo root.
#
# Reference:
#   https://www.swift.org/documentation/docc/distributing-documentation-to-other-developers
#   https://github.com/swiftlang/swift-docc-plugin

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="${REPO_ROOT}/docs"
mkdir -p "$OUTPUT_DIR"

echo "Generating DocC for ManifoldKit + ManifoldRuntime + ManifoldXPC..."
swift package \
  --allow-writing-to-directory "$OUTPUT_DIR" \
  generate-documentation \
  --target ManifoldKit \
  --target ManifoldRuntime \
  --target ManifoldXPC \
  --output-path "$OUTPUT_DIR" \
  --transform-for-static-hosting \
  --hosting-base-path manifold

echo "DocC output: $OUTPUT_DIR"
echo "Open the local index:"
echo "  open '$OUTPUT_DIR/index.html'"
