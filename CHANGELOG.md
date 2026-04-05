# Changelog

All notable changes to Manifold are documented here.

## [0.3.0] - 2026-04-05

### Added
- Versioned database migration system: numbered migrations tracked in `schema_migrations` table. Replaces ad-hoc ALTER TABLE pattern. Future schema changes slot in as new numbered migrations.
- Error banners: user-visible error overlay in MainView when database operations fail. No more silent empty screens.
- os.Logger: structured logging in AuditStore, DatabaseConnection, and ManifoldStore for debugging production issues.
- Accessibility labels on all color indicators, status icons, and interactive elements across every view. Screen reader support from zero to complete.
- Raycast-style onboarding: welcome step shows feature preview cards, each setup step shows what it activates ("Activates: file browsing, search, version history..."), "I don't use Apple Mail" skip option.
- GitHub Actions CI: build + test on every push to main and feat/* branches. Release workflow creates GitHub Release with zip on version tags.
- Distribution: enhanced build.sh reads VERSION file, supports release mode, creates signed .app bundle with zip archive for GitHub Releases.
- ConfigWriter: injectable home directory for testing. 7 new tests covering merge safety (preserving existing MCP servers during install).
- ManifoldBridge: 5 new tests covering write path (modification tracking, auto-run creation, audit logging, email rejection).
- DatabaseMigrator: 5 new tests (fresh version, migrate all, idempotent, upgrade existing DB, persistence).

### Changed
- MCP access control: paused/archived sources no longer leak files to agents (positive allowlist filter). Smart path resolution strips source folder name prefix from agent-submitted paths.
- get_status now reports active vs paused sources with per-source detail, including all-paused warning state.
- Source removal uses distinct "removed" status, separate from "archived" (paused). Removed sources hidden from both dashboard and MCP.
- Content search dispatched to background thread. Name and activity filters debounced at 150ms.
- ManifoldStore: core data loading (refresh, loadWorkspaces, loadSessions) uses proper error handling instead of silent try?.
- Source management (add, remove, pause, resume) and run lifecycle (start, end) propagate errors to UI.

### Fixed
- Paused sources were visible to MCP agents (security fix).
- Nested directory creation on write when AI agents prefix source folder name to paths.
- Could not remove folders from Manifold (remove and pause used identical status).
- DatabaseConnection ROLLBACK failure silently swallowed (now logged).
- AuditStore metadata serialization failure silently swallowed (now logged).

## [0.2.0] - 2026-04-05

### Added
- Session Replay: see everything an AI agent did in a chronological timeline with inline diffs. Expand any write event to see exactly what changed. Revert any file to its state before the agent touched it.
- Email View: dedicated sidebar tab for managing which emails AI agents can see. Toggle shared/hidden per email. Filter by shared, hidden, or all. Email rules management inline.
- Sources Dashboard: the main view is now focused on your source folders. Each folder has a visible Active/Paused toggle and an overflow menu for secondary actions (Reveal in Finder, Remove). No more hunting through right-click context menus.
- Spacing System: consistent base-4 spacing scale (4/8/12/16/24/32) across all views. Defined in `Components/Spacing.swift` and documented in `DESIGN.md`.
- ColorIndicator Component: reusable colored dot indicator replacing 15+ inline Circle instances.
- DiffView line numbers: diffs now show line numbers for easier reference. Padding fixed from 1px to 4px for readability.

### Changed
- Sidebar redesigned with Raycast-inspired left accent bar on selection, 5 tabs (Sources, Files, Activity, Emails, Versions), breathing room between items, and connection status footer with divider.
- Activity View: filter picker changed from segmented control to dropdown menu. Session grouping with collapsible sections, contextual bottom bar with Copy Summary and Export.
- Files View: replaced `.searchable()` (caused macOS 26 toolbar crash) with inline search field. Simplified filter bar.
- Onboarding: larger frame (580x480), thicker progress bar (4pt).
- Settings: renamed technical terms ("Garbage Collect" to "Clean Up Storage", "Prune Old Runs" to "Remove Old Versions").
- DESIGN.md updated with spacing scale, typography weight rules, and list style documentation.

### Fixed
- Fixed SF Symbol name `clock.arrow.counterclockwise` (invalid) in VersionDetailView.
- Fixed `ALTER TABLE` crash on re-launch when `session_id` column already exists.
- Removed `.searchable()` modifier that caused `NSToolbar` duplicate item crash on macOS 26.
