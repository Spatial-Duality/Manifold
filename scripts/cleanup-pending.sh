#!/usr/bin/env bash
#
# scripts/cleanup-pending.sh
#
# Run this once after pulling the post-reorganization commit. It deletes the
# items the in-session sandbox couldn't remove on its own (build outputs that
# Xcode marks read-only, the parking-lot directory, and the third-party logo
# folder that should never be committed).
#
# Idempotent — run again any time and it's a no-op.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Repository root: $ROOT"

# 1. Build artefacts (massive — about 11 GB total at the time of writing).
#    Xcode chflags-protects some files inside DerivedData; sudo may be needed
#    on the truly stuck ones. Run as you, not as root, first.
echo "==> Removing build outputs (.build, .deriveddata-*, .gstack)…"
chflags -R nouchg .deriveddata-* .build .gstack 2>/dev/null || true
rm -rf .build .gstack .deriveddata-* || {
  echo "    Some files were chflags-protected. Retrying with sudo (you'll be prompted)."
  sudo chflags -R nouchg .deriveddata-* .build 2>/dev/null || true
  sudo rm -rf .build .gstack .deriveddata-* || true
}

# 2. Stale loose files at the root that the reorg parked aside.
echo "==> Removing stale loose files at root…"
rm -f default.profraw

# 3. Third-party logos — never to be committed.
echo "==> Removing 'SVG External logo files/' (Anthropic / Claude / Codex marks)…"
rm -rf "SVG External logo files"

# 4. Empty leftover directories from the design/, codex/, and reverted CI moves.
echo "==> Removing empty leftover directories…"
[ -d design ] && rmdir design/html 2>/dev/null || true
[ -d design ] && rmdir design 2>/dev/null || true
[ -d codex ] && rmdir codex/tasks 2>/dev/null || true
[ -d codex ] && rmdir codex 2>/dev/null || true
[ -d .github/workflows ] && rmdir .github/workflows 2>/dev/null || true

# 5. Parking lot — hold-area for files the in-session sandbox could move but
#    not delete. Includes the old VERSION file, Codex tooling docs, and any
#    test artefacts.
echo "==> Removing .trash-pending-user-delete/…"
rm -rf .trash-pending-user-delete

# 6. Final report.
echo
echo "==> Done. Remaining at root:"
ls -1 . | grep -v "^\."
echo
echo "==> Untracked + ignored summary (top 20):"
git status --ignored --short | head -20 || true
