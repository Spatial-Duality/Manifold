# Changelog

All notable changes to Manifold are documented here.

## [Unreleased]

### Added — Access redesign (Cowork-First UI, 2026-04-28)
- Per-AI sharing chip stack across the entire access surface. Folders Matrix, Files Flat, and Mail Threads each render one chip per connected AI (filled when shared, hollow when hidden, agent-tinted on tap) — the same `AccessChipStack` component everywhere. Replaces the old single-agent dropdown in Mail.
- Drag-and-drop folders or files from Finder onto the Folders or Files surface. Folders add immediately; files raise a confirmation dialog asking whether to add the whole containing folder or only that file. "Add only this file" scopes the parent for every connected AI and writes per-file deny overrides for the existing top-level siblings via the bulk override endpoint.
- Folders Matrix gains a labelled **Sharing** column that mirrors the row's checkboxes: `Not shared` / `Shared with Claude` / `Shared with Codex` / `Partly shared · N of M` / `Shared with all` (or `Shared with both` for a 2-AI setup). A small attention-coloured dot beside the pill flags sources that have explicit per-file overrides; the inspector still owns the per-file detail.
- Source health pills (`Removed`, `Offline`) moved inline next to the folder name — they describe whether the folder exists on disk, not how it's shared.
- Mail thread table prioritises Subject (the highest-information column) over Sender; widths rebalanced across Sender / Subject / Mailbox / Received / Attach so Subject takes the slack on narrow windows.
- Mail message inspector now shows a real scrollable body (`bodyText` extracted from the .eml, fall back to `preview`), 220–360pt tall, selectable, line-spaced. A bordered **Open in Mail** button beside the Message header hands the original `.eml` to `NSWorkspace.shared.open` so the user lands in their default eml handler.
- File inspector preview opens in the default app on double-click, matching Finder.
- Inspector header in the folder tree pane tightens — chip strip moved below the title row, single-AI setups drop the redundant "Editing X overrides" caption, multi-AI picker is `.controlSize(.small)`.
- New `AgentMeta.stableKey([TargetApp])` helper replaces three duplicated `connectedAgentsKey` views; new `ManifoldStore.fileVisibilityOverridesByAgent(_:)` loads overrides for a list of agents in parallel via TaskGroup; new `View.manifoldFileDropTarget(store:)` modifier consolidates the drop UX into a single component shared by Folders and Files.
- `MailReviewModel` now tracks per-agent shared sets (`sharedEmailIDsByAgent`) and exposes `sharedAgents(for:)`, `setMessageShared(_:agent:isShared:)`, `setMessageSharedForAllAgents(_:isShared:)`. The view pushes the live `connectedAgents` list in via `setConnectedAgents` so chips track which AIs are activated, no greyed-out options.

### Changed — Access redesign
- `MailReviewRow` carries a precomputed `sharedAgents: Set<TargetApp>` so the Share TableColumn cell renders from the row instead of re-querying the model on every cell render. `sharedAnyAgentCount` is now a stored property recomputed inside `refreshSharedState` rather than allocating a fresh Set on every body pass.
- `loadDriftCounts` and `loadOverrides` fan out per-agent XPC calls via `withTaskGroup` and only republish state when it actually changed, so `@Observable` doesn't fire on no-op refreshes.
- `addSourceForSingleFile` writes deny overrides via `setManyFileVisibilityOverrides` (one XPC roundtrip) by downcasting `runtime` to `AppRuntimeClient`; falls back to per-record loop for fixture clients.
- `mutateScope` in `ManifoldStore` reads-modifies-writes the whole `AgentAccessPolicy` struct so `@Observable` fires reliably on optional-value-type mutation. Previously the per-agent column failed to unselect after toggling.
- The "Both" tri-state checkbox in the Folders matrix recomputes scope from live store state at click time, so a `.mixed` cell always moves toward "shared with all" rather than flipping off mid-cycle.

### Fixed — Access redesign
- `EXC_BREAKPOINT` crash on the Mail surface caused by reading an `@Observable` `MailReviewModel` from inside a SwiftUI Table cell — TableColumn cells on macOS don't reliably propagate environment values. State + actions are now passed into share cells explicitly.
- Files Access column was using a labelled `AccessCheckboxStrip` with `.fixedSize(horizontal:)` that visually overflowed into the Name column on narrow windows. Switched to the chip-only `AccessChipStack`; per-row All/Allow/Deny/Reset still lives in the bulk bar and inspector.
- Mail inspector defaulted to open and auto-opened on row select. Now starts hidden, opens only on double-click (or via the toolbar toggle / ⌥⌘0), with a close button on the inspector itself.

### Added — Personal Data OS (earlier in cycle)
- Personal Data OS stores for scoped memory, ledger entries, tool metrics, capability handles, knowledge graph nodes, saved skills, exec runs, and fabrication findings.
- Runtime-backed memory settings: `amnesiacMode`, `derivedRetentionDays`, memory origins, and retention expiry via `expired_by_retention`.
- XPC/app commands for reading and updating memory settings, with Access and Storage surfaces bound to runtime state instead of local UI-only preferences.
- Strict claimed-action verification against scoped exposure records. Structured `content_hash` or `tool_name + resource_path` claims can be `supported`; weak text-only claims are `ambiguous`; missing scoped evidence is `unverified`.
- Regression coverage for scoped memory deletion, scoped capability handles, memory retention, amnesiac mode, timestamp-covered ledger hashes, legacy ledger verification, and strict claim verification.

### Changed — Personal Data OS
- `forget_memory` now loads the memory item and checks source/grant lineage before tombstoning. Missing and out-of-scope memory IDs return the same generic denial.
- `check_capability_flow` now scopes value handles before evaluating sinks or Rule-of-Two policy.
- New ledger entries include stable timestamp material in their tamper-evident hash. Legacy no-timestamp rows still verify, with a warning that reports how many rows are not timestamp-covered.
- Memory recall, prior-context reuse, graph queries, and app memory listing expire derived memory before returning results.
- MCP tool documentation now describes structured claim proof semantics and scoped memory/capability behavior.

### Fixed — Personal Data OS
- Privacy controls for memory are no longer cosmetic: amnesiac mode blocks derived-memory writes and retention tombstones expired derived memory.
- Claim verification no longer marks loose global ledger/exposure text matches as proof.
- Out-of-scope memory and capability IDs can no longer be mutated or queried merely because the caller has some active Manifold access.

## [0.5.0] - 2026-04-17

### Added
- Unified Rules system: a single `RuleRecord` grammar (`scope × matcher × action × agents × window × source`) covers files, emails, and agent behavior. New `Sources/ManifoldKit/RuleTypes.swift`, `RuleStore.swift`, `RuleEngine.swift`, and `RuleSeed.swift`.
- Live enforcement: `ManifoldBridge.enforceFileReadRules` calls `RuleEngine.evaluate` on every governed file read. Email engine re-pointed at the same store. Agent-behavior rules gate tool invocations and session duration.
- Seeded denies ship on by default and pin to the top of their group: `**/.env*`, `**/.ssh/**`, `**/*.pem`, `**/*.key`, `**/id_rsa*`, `**/.aws/credentials`, `**/.gnupg/**`, `**/.netrc`, `**/.npmrc`, `**/.git/config`, detected token/key patterns, and password-reset / 2FA mail shields.
- Top-level Rules tab in the ledger (Activity / Access / Mail / Requests / Rules, ⌘1–⌘5) with a split-view authoring surface: filterable sidebar, sortable SwiftUI `Table`, inline inspector with a sentence-style `RuleBuilder`, and `MatchPreview` showing what a rule would block right now.
- Settings ▸ Rules pane for global defaults (per-agent default policy, restore seeded rules). Authoring stays in the ledger.
- Deny-wins + first-match precedence, with shadow warnings in the inspector when a user rule is pre-empted by a seeded rule, and an explicit user-override-allow path for rare overrides.
- First-launch migration reads existing `EmailRuleSet` / shields and imports them into `RuleStore` tagged `source = .imported`.
- `LocalFileProtection`: owner-only (0o700) governance directory, 0o600 file perms.
- `ProtectedStorageCrypto`: AES-GCM at-rest encryption for sensitive payloads with the key held in the macOS Keychain and an `MNF1` magic header for future migrations.
- `ScopedFileIdentity`: path normalization (resolves `..`, rejects symlink escapes, strips source-folder prefixes) applied before any policy check.
- `FileVisibilityOverrideStore`: per-agent file-level visibility overrides that cohere with rule decisions.
- `StandingWriteApprovalStore`: once vs. default answers for standing-write prompts survive session boundaries.
- `SignedProcessVerifier`: XPC callers are checked against a code-signing requirement string before the service accepts privileged calls. Forged agent labels on unsigned binaries are rejected at the boundary.
- `RuleEngineTests` covering precedence, combinators, per-agent filtering, and shield translation.

### Changed
- `EmailPolicyEngine.decision` refactored to consume `RuleRecord`. The old 10-step hierarchy is gone; decisions still carry reason strings so the UI does not regress.
- `HistoryModel` audit entries include `matchedRuleID` and explanation strings. Inspector's "Recent matches" list is backed by real audit data.
- App shell: `LedgerView` is a single `NavigationSplitView` (sidebar, detail, toolbar, status bar). Live session chip moved to `StatusBar` only — one ambient home for runtime state. Sidebar sets no `navigationTitle` (detail owns it) so rows do not render behind traffic lights on macOS 26.
- `LedgerToolbar` keeps Start/Finish session primary actions and Refresh runtime; title-bar stays populated so macOS does not collapse it alongside a collapsed sidebar.
- `Mail` destination renamed internally to mail review, distinguishes never-synced vs. paused vs. has-last-sync empty states honestly.
- `Requests` sidebar no longer renders blank when empty; pending counts use `.badge(Text?)` with "99+" truncation handled in `LedgerSidebar.badgeText(for:)`.
- Default policy per agent preserved from today: Claude (cowork) = allow-unless-blocked, Codex = block-unless-allowed. Extended from email-only to files.

### Fixed
- Sidebar rows rendering behind the title bar when the sidebar also set `.navigationTitle` (the detail column owns the window title on macOS).
- Preview-only `RulesWindowView` replaced with real enforcement; old file kept as an empty shim so the Xcode project reference still compiles during transition.
- Seed-deny ordering bug where user rules could accidentally open a hole by being dragged above a seeded deny — fixed by the two-phase precedence.
- `.claude/worktrees/` and `ManifoldApp/build/` added to `.gitignore` so ~540 MB of artifacts no longer land in commits.

## [0.4.0] - 2026-04-08

### Added
- Email backup infrastructure: IMAP sync engine with per-account connection management, .eml file storage, FTS5 full-text search, and body text background backfill with progress tracking.
- EmailStore: extracted from GrantStore into a dedicated store with unified condition builder, smart mailbox rule engine, and composable search across sender, subject, body text, and metadata fields.
- Smart mailbox editor: create custom mailboxes with AND/OR rule logic, field conditions (equals, contains, before/after, between), and live result counts.
- .manifoldignore: gitignore-style per-source exclusion files. Supports wildcards, double-star, negation, directory-only, and anchored patterns. Excluded files are skipped during both materialization and size estimation.
- Pre-session preview: before granting AI access, users see file count per source, total size, email count, and sensitivity-filtered email visibility. Five interaction states (computing, error, no-sources, preview, cancel) with Liquid Glass button styles on macOS 26.
- Domain presets wired into session behavior: email sensitivity (strict/moderate/open) and summary framing now flow from preset selection through grant creation to MCP tool filtering. "Legal Review" actually filters emails differently than "General."
- EmailSensitivityFilter: domain-based email filtering with curated deny lists for banking, health, and 2FA domains.
- Migration v10: email backup state columns, FTS5 virtual table, mailbox membership tracking, junk backfill.
- Migration v11: grant email_sensitivity and summary_framing columns.
- 33 new tests covering EmailStore operators, MaterializationEngine estimation, GrantTypes, and GlobMatcher patterns.

### Changed
- GrantStore refactored: email-related methods extracted to EmailStore. Grant types extracted to GrantTypes.swift. GrantStore focused on grant lifecycle only.
- SessionPreviewCard redesigned with decision-payload-first hierarchy: "Grant AI access to N sources" header, summary line, per-source breakdown, email sensitivity context, and size warnings using system semantic colors.
- DashboardView session banner: 5 states (computing, error, preview, active, idle) with glass button styles and VoiceOver accessibility labels.
- GlobMatcher: regex pre-compiled at init instead of per-match call. Order-of-magnitude improvement for large source trees.
- ManifoldBridge readEmail: single-row lookup via emailMessage(id:) instead of fetching 5000 rows. isEmailAccessible helper consolidates visibility checks.
- Materialization copy loop wrapped in do/catch with partial mount cleanup on failure.

### Fixed
- FTS5 duplicate entries on re-index: stale entry deleted before inserting updated body text.
- FTS5 orphan entries on account deletion: entries cleaned before DELETE FROM email_messages.
- SQL injection defense-in-depth: sqlForCondition re-validates field against allowedFields whitelist.
- deleted_on_server_at filter used != '' which misses NULL rows. Added isNotNull operator.
- .today and .thisWeek quick filters returned nil (unfiltered). Added inline date-relative SQL.
- EmailSyncEngine isStopped never reset after stop(), permanently killing sync. Now resets on register().
- Orphan materialization cleanup could delete active session data on transient DB errors. Now distinguishes "not found" from "error."
- Removed unnecessary await on synchronous EmailStore methods in ManifoldBridge.

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
