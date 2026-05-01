#!/usr/bin/env bash
set -euo pipefail

MODE="print"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --checklist|--print)
      MODE="print"
      shift
      ;;
    --markdown)
      MODE="markdown"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

print_plain() {
  cat <<'EOF'
Manifold live smoke checklist
=============================

Purpose
- Manual or nightly validation against real integrations that CI should not depend on.
- This is a checklist, not an automated pass/fail harness.

Prerequisites
- Debug or release Manifold app build available locally.
- Real sacrificial IMAP mailbox configured for testing.
- Privacy Filter model install path available on the test machine.
- Manifold runtime can launch locally.
- Optional: Codex/Claude configured to use Manifold MCP only for the final governed path check.

Lane 1: Runtime and model
1. Launch Manifold and confirm the main ledger opens without fixture mode.
2. Open Settings > Privacy.
3. Install the configured privacy backend if needed.
4. Verify the backend reports as loaded or ready.
5. Confirm index status loads and no silent error state is shown.

Lane 2: Real email sync
1. Add or enable the sacrificial IMAP mailbox.
2. Trigger a sync and wait for the mailbox to populate.
3. Verify at least one email with body text and one attachment appear in Mail.
4. Confirm privacy smart mailboxes appear:
   - Has My Info
   - Has Secret
   - Third-Party Private
   - Org Only
   - Needs Review
5. Confirm at least one privacy-indexed email is visible in the expected smart mailbox.

Lane 3: Governed privacy flow
1. Add a source folder containing:
   - one plain text file with personal info
   - one document with a secret or account number
   - one unsupported binary
2. Wait for privacy indexing to settle.
3. Verify Settings > Privacy shows indexed, failed, and stale counts consistent with that corpus.
4. Verify the unsupported file is represented as failed or partial, not silently skipped.
5. Confirm a privacy review request appears when governed content requires approval.
6. Resolve one request as Share Redacted and verify the queue updates.
7. Resolve one request as Share Original Once and verify it does not persist as a standing approval.

Lane 4: Activity and evidence
1. Open Activity and filter to Privacy.
2. Select the latest privacy event.
3. Verify the evidence pane shows:
   - privacy summary
   - matched categories
   - backend/model metadata
4. Confirm the activity record matches the action just taken in the request queue.

Lane 5: MCP-only governed path
1. Start a fresh governed session using only Manifold MCP tooling.
2. Perform one read or search that touches indexed content.
3. Verify the request, decision, and resulting activity event all appear in Manifold.
4. Confirm the delivered result matches the selected privacy action.

Exit criteria
- The app remains stable across all lanes.
- Real email sync works end to end.
- Privacy model install/warm status is correct.
- Privacy requests, smart mailboxes, and evidence views stay consistent.
- Unsupported formats remain visible as unsupported or partial.

Notes
- Keep this checklist aligned with the app’s current navigation, accessibility IDs, and privacy terminology.
- Do not use production inboxes or secrets for this run.
EOF
}

print_markdown() {
  cat <<'EOF'
# Manifold Live Smoke Checklist

## Purpose
- Manual or nightly validation against real integrations that CI should not depend on.
- This is a checklist, not an automated pass/fail harness.

## Prerequisites
- Debug or release Manifold app build available locally.
- Real sacrificial IMAP mailbox configured for testing.
- Privacy Filter model install path available on the test machine.
- Manifold runtime can launch locally.
- Optional: Codex/Claude configured to use Manifold MCP only for the final governed path check.

## Lane 1: Runtime and model
1. Launch Manifold and confirm the main ledger opens without fixture mode.
2. Open Settings > Privacy.
3. Install the configured privacy backend if needed.
4. Verify the backend reports as loaded or ready.
5. Confirm index status loads and no silent error state is shown.

## Lane 2: Real email sync
1. Add or enable the sacrificial IMAP mailbox.
2. Trigger a sync and wait for the mailbox to populate.
3. Verify at least one email with body text and one attachment appear in Mail.
4. Confirm privacy smart mailboxes appear: `Has My Info`, `Has Secret`, `Third-Party Private`, `Org Only`, `Needs Review`.
5. Confirm at least one privacy-indexed email is visible in the expected smart mailbox.

## Lane 3: Governed privacy flow
1. Add a source folder containing one plain text file with personal info, one document with a secret or account number, and one unsupported binary.
2. Wait for privacy indexing to settle.
3. Verify Settings > Privacy shows indexed, failed, and stale counts consistent with that corpus.
4. Verify the unsupported file is represented as failed or partial, not silently skipped.
5. Confirm a privacy review request appears when governed content requires approval.
6. Resolve one request as `Share Redacted` and verify the queue updates.
7. Resolve one request as `Share Original Once` and verify it does not persist as a standing approval.

## Lane 4: Activity and evidence
1. Open Activity and filter to Privacy.
2. Select the latest privacy event.
3. Verify the evidence pane shows privacy summary, matched categories, and backend/model metadata.
4. Confirm the activity record matches the action just taken in the request queue.

## Lane 5: MCP-only governed path
1. Start a fresh governed session using only Manifold MCP tooling.
2. Perform one read or search that touches indexed content.
3. Verify the request, decision, and resulting activity event all appear in Manifold.
4. Confirm the delivered result matches the selected privacy action.

## Exit criteria
- The app remains stable across all lanes.
- Real email sync works end to end.
- Privacy model install/warm status is correct.
- Privacy requests, smart mailboxes, and evidence views stay consistent.
- Unsupported formats remain visible as unsupported or partial.
EOF
}

case "$MODE" in
  print) print_plain ;;
  markdown) print_markdown ;;
esac
