# Changelog

All notable changes to Manifold are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-06-10

Focus feature: rename the Work pane to Focus, replace ad-hoc session
templates with first-class saved Focuses, and surface the picker as
the primary mental model. Default Focus is always running on startup.
A custom Focus saves a complete bundle of folder scope, per-file
overrides, and runtime settings (request detail, file memory, note
capture, email sensitivity), and switching between them is a one-click
atomic swap.

### Added
- Focus pane (renamed from Work) with sidebar Focus picker, inline
  rename, right-click context menu (Activate / Rename / Set as default
  at launch / Delete), and ⌘1–⌘9 hot-switching.
- Locked Down built-in Focus (empty scope, conservative settings) and
  Default built-in Focus (per-agent independent like today's Access
  matrix). Built-in Focuses cannot be deleted.
- Active session card with Apple-native Toggle for activation, segmented
  Apply-to picker (Claude / Codex / Both), and a per-Focus mirror
  toggle that controls whether the scope editor links Claude and Codex
  columns or treats them independently.
- Inline Sync now button next to the mirror toggle, persisting the
  one-shot mirror result into the active Focus's saved preset rows so
  the change survives Focus deactivation/reactivation.
- Optimistic UI flip on Focus activation: the toggle and navigation
  subtitle update on the same frame as the click; full refresh
  replaced with a targeted grant-state refresh.
- Folder color cue based on per-AI sharing state (green = both AIs,
  Claude orange = Claude only, Codex blue = Codex only, neutral =
  neither). Mirror-state badge in the Folders matrix toolbar.
- ContentUnavailableView empty states for Focuses, Activity timeline,
  and the Inspector when nothing is selected.
- Focus chip in the macOS title bar via .navigationTitle +
  .navigationSubtitle so the running Focus is visible everywhere.
- Durable source identity. Sources carry a security-scoped bookmark,
  resolved root path, and health status, so a shared folder follows
  Finder moves and renames instead of breaking, the runtime fails closed
  when a source disappears, and the Access UI offers repair.
- One-field mail setup for custom-domain accounts. "Other IMAP" setup
  resolves the server automatically (domain autoconfig, the Thunderbird
  ISPDB, then DNS SRV — TLS-on-connect results only), so most accounts
  need just an address and password. Manual server entry stays as the
  fallback when discovery finds nothing.

### Changed
- Mail sync is substantially faster. Message bodies download in batched
  IMAP fetches, and the next batch downloads while the current one is
  parsed, encrypted, and indexed. Per-message database writes are now
  grouped into one transaction per batch, and envelope metadata fetches
  in batches of 200 instead of 50.
- Access and Finder workflows hardened from alpha feedback, with MCP
  health checks, request IDs, effective access snapshots, durable
  failure recording, and restart/disconnect probes to reduce flaky
  runtime failures.
- Toolbar consolidated to .toolbar { ToolbarItemGroup(placement:
  .primaryAction) } for auto-Liquid-Glass on macOS 26.
- Activity always shown; Approvals only render when viewing the
  currently-active Focus.
- Default Focus's "default-at-launch" indicator is now a star in the
  sidebar row, not a separate pill.
- Inspector defaults hidden until the user opens it via the toolbar.

### Removed
- Settings → Sessions tab (replaced by the Focus sidebar).
- "Cross-agent mirror" section in Settings → Advanced (the Mirror sheet
  is now inline in the active card; the global auto-mirror toggle is
  obsolete because mirror state is per-Focus).
- Custom chip controls (FocusChipMenu, DefaultAtLaunchChipMenu),
  ManageFocusesSheet, NewFocusSheet — replaced by sidebar + inline
  Toggle/Picker.

### Fixed
- Helper version drift: the runtime helper hardcoded "0.4.0" while the
  app target was bumped to 0.4.2, triggering an auto-restart loop on
  every launch that left the XPC connection in a fragile state.
  Introduced ManifoldVersion.current as a single source of truth that
  both the helper and the app read.
- Stale-rebuild signature spam: privileged app commands now distinguish
  a stale rebuild (on-disk binary still well-signed) from a genuinely-
  invalid signature, so local-development rebuilds no longer flood the
  log with "Caller signature is invalid".
- Built-in Focus flags: a one-shot correction migration repairs Default
  Focuses seeded under v43 that ended up with column-default values
  (mirror_to_both=1, is_built_in=0) instead of the intended
  (false, true).

## [0.4.0] - 2026-05-03

Initial public release. The app, runtime, MCP bridge, on-device PII
filter, version history, and audit log are all in this version.

### Added
- SwiftUI Mac app for governing what Claude and Codex can see.
- `manifold-mcp` MCP server. Registers automatically with Claude
  and Codex Mac apps (and the CLI variants if installed) via
  `manifold-mcp --install`.
- Per-AI per-file allow/deny across Claude and Codex. Default-deny on
  contracts, payroll, tax filings, and other sensitive paths.
- Mail support for iCloud, Gmail, and Microsoft 365 (plus IMAP).
  Inbox is denied by default; grant per message or thread, per AI.
- Tracked Work Blocks for AI-proposed writes. Deny, Allow once, or
  Add to default; previous versions remain recoverable.
- Version snapshots per file, accessible from any later chat.
- AI-usage audit log with timestamp, matched rule, and file version.
  Stays on your Mac.
- On-device PII filter (OpenAI Privacy Filter on MLX) as a preflight
  rule. Masks, warns, or blocks 2FA codes, addresses, names, phone
  numbers, account numbers, government IDs.
- Sparkle update path with EdDSA-signed appcast.
- AES-GCM encrypted local governance database (rules, grants,
  exposure records, snapshots, scoped memory) keyed from the
  Keychain.

### Security
- No product telemetry.
- Network access is limited to explicit user-facing flows such as mail,
  OAuth, downloads, and Sparkle updates.
- Audit trail records both what was exposed and whether the PII
  filter ran.

[Unreleased]: https://github.com/Spatial-Duality/Manifold/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Spatial-Duality/Manifold/releases/tag/v0.5.0
[0.4.0]: https://github.com/Spatial-Duality/Manifold/releases/tag/v0.4.0
