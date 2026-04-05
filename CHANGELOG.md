# Changelog

All notable changes to Manifold are documented here.

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
