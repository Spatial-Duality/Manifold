# Manifold — Polish Backlog

> **What this is**: Ticket-sized work items organized into four phases. Each item has a compact spec: what, why, where, dependencies, acceptance criteria, and review artifacts. Hand this to Claude Code.
>
> **References**: Findings in POLISH-AUDIT-v2.md. Standards in DESIGN-STANDARDS.md. Surface-level redesign in REDESIGN-PLAN-v5.2.md. Menu bar in MENU-BAR-SPEC.md.
>
> **Sequencing rule**: Phase A (Foundation) must complete before Phases B–D begin. Within B–D, items are independent unless a dependency is noted.
>
> **Assumes**: v5.2 and menu bar spec are implemented.

---

## Phase A — Foundation

Everything in this phase is a shared primitive. Completing these first prevents repainting surfaces twice.

**Phase estimate**: 28–35 hours (includes design, implementation, QA, and iteration)

---

### A-01: Asset catalog and named colors

**Goal**: Create `Assets.xcassets` with all color sets defined in DESIGN-STANDARDS §1. Replace every hardcoded color literal in the codebase.

**Why**: Unblocks dark mode correctness, high contrast, and color consistency across all surfaces.

**Affected files**: New `Assets.xcassets` directory. Then every file containing `.blue`, `.purple`, `.green`, `.orange`, `.red` as a semantic color (40+ files per audit).

**Depends on**: Nothing. Do this first.

**Acceptance criteria**:
- `Assets.xcassets` exists with `AppIcon.appiconset` (placeholder OK), `AccentColor`, `ClaudeBlue`, `CodexPurple`, `StatusActive`, `StatusPaused`, `StatusWarning`, `StatusDanger`
- Every color set has both Any Appearance and Dark Appearance variants
- Zero `.blue` / `.purple` / `.green` / `.orange` / `.red` literals used for semantic meaning remain (grep to verify)
- Light mode, dark mode, and Increase Contrast all render correctly

**Review artifacts**: Before/after screenshots (light + dark mode) of Overview, Files, Emails.

**Out of scope**: App icon design (separate item A-02). Accent color override (using system default per DESIGN-STANDARDS §1.1).

---

### A-02: App icon design

**Goal**: Design and implement a custom app icon at all required sizes.

**Why**: The single most impactful first-impression change. The Dock currently shows a generic icon.

**Affected files**: New `AppIcon.appiconset` in `Assets.xcassets`. `Info.plist` if icon config needed.

**Depends on**: A-01 (asset catalog exists).

**Acceptance criteria**:
- 1024×1024 master icon exists
- All macOS required sizes generated (16, 32, 64, 128, 256, 512, 1024 @1x and @2x)
- Icon reads correctly at 16px in Dock/Finder
- Icon works on both light and dark desktop backgrounds
- Communicates: protection, visibility, trust

**Review artifacts**: Icon renders at 16px, 32px, 128px, 512px on light and dark backgrounds.

**Out of scope**: App Store marketing screenshots.

---

### A-03: Menu bar custom icon

**Goal**: Design a monochrome template image for the menu bar at 18×18pt.

**Why**: `shield.checkered` is unrecognizable among other menu bar items.

**Affected files**: New `MenuBarIcon.imageset` in `Assets.xcassets`. `ManifoldApp.swift` label reference.

**Depends on**: A-01, A-02 (icon language should derive from app icon).

**Acceptance criteria**:
- Template image at 1x and 2x
- Renders correctly as menu bar template (system manages tint for light/dark/active states)
- Recognizable at 18×18pt among 15+ other icons

**Review artifacts**: Screenshot of menu bar with 10+ other icons visible.

**Out of scope**: Animated states.

---

### A-04: Typography scale

**Goal**: Implement the type scale from DESIGN-STANDARDS §2 as shared `ViewModifier` or `Font` extensions. Audit and replace every ad-hoc `.font()` call.

**Why**: Typography is the primary visual system. Inconsistency makes the app feel assembled from parts.

**Affected files**: New `Typography.swift` (or extend `Spacing.swift`). Then every SwiftUI view with `.font()` calls (78+ files).

**Depends on**: Nothing. Can parallel A-01.

**Acceptance criteria**:
- `Type.sectionTitle`, `.heading`, `.body`, `.secondary`, `.caption`, `.mono`, `.numericBody`, `.numericCaption` all defined
- Every `.font()` call in the codebase maps to a named role (grep for orphan `.font(` calls)
- All numeric data uses `.monospacedDigit()` — file counts, email counts, byte sizes, timestamps
- All file paths use `Type.mono` + `.truncationMode(.middle)`

**Review artifacts**: Before/after screenshots of SourcesTableView, DomainsTableView, VersionDetailView (typography-dense surfaces).

**Out of scope**: Dynamic Type scaling (verified in A-10).

---

### A-05: Design token completion

**Goal**: Add shadow presets, opacity scale, and animation presets to the design system per DESIGN-STANDARDS §§3–5.

**Why**: Without shared presets, every implementation invents values. Visual drift accumulates.

**Affected files**: New or extended token file(s). Then every file with inline shadow, opacity, or animation values.

**Depends on**: Nothing. Can parallel A-01 and A-04.

**Acceptance criteria**:
- `Opacity.rowTint`, `.badgeFill`, `.hoverHighlight`, `.disabled`, `.scrim` defined and used everywhere
- `Shadow.card`, `.cardHover`, `.popover`, `.toast` defined as `ViewModifier` extensions
- `Anim.stateChange`, `.structural`, `.entrance`, `.micro`, `.none` defined
- Zero `.easeInOut`, `.easeIn`, `.easeOut`, `.linear` remain in animation calls (grep to verify)
- Every animation checks `accessibilityReduceMotion`

**Review artifacts**: Grep results showing zero legacy animation curves. Demo of card hover → shadow transition.

**Out of scope**: Adding new micro-animations (that's B-phase).

---

### A-06: Unified badge component

**Goal**: Replace all inline capsule/pill implementations with one `Badge` component per DESIGN-STANDARDS §6.

**Why**: Badges are core visual language. Three different capsule patterns undermine status-at-a-glance.

**Affected files**: New `Badge.swift` component. Then `StatusBadge.swift`, `AgentBadge.swift`, `AgentPolicyCard`, connection indicators, and every inline capsule.

**Depends on**: A-01 (named colors), A-04 (typography), A-05 (opacity tokens).

**Acceptance criteria**:
- `Badge` component with `.info`, `.success`, `.warning`, `.danger`, `.neutral` variants
- `.compact`, `.standard`, `.prominent` size variants
- All existing capsule/pill patterns migrated to use `Badge`
- Every badge has `.accessibilityLabel` describing state in words
- Visual consistency across all surfaces (same padding, radius, font, opacity)

**Review artifacts**: Screenshot collage of every badge instance in the app.

**Out of scope**: New badge locations (e.g., sidebar counts — those come in Phase B).

---

### A-07: Empty state component

**Goal**: Build a shared empty state system per DESIGN-STANDARDS §7. Replace every placeholder `ContentUnavailableView`.

**Why**: Empty states are the first thing new users see. Placeholder empties communicate "unfinished."

**Affected files**: New empty state component/helpers. Then every view with `ContentUnavailableView` or empty-state handling (~11 locations per audit).

**Depends on**: A-04 (typography), A-01 (colors).

**Acceptance criteria**:
- Full-surface, section, and inline empty state patterns implemented
- Every empty state answers: what would be here, why is it empty, what to do next
- Conditional differentiation: not configured vs. configured-but-empty vs. filtered-empty
- Email Smart Mailbox section uses section-level pattern (not full-surface)
- All copy follows DESIGN-STANDARDS §10 content design rules

**Review artifacts**: Screenshot of every empty state in the app (light mode). List of all empty state copy.

**Out of scope**: Loading states (A-08). Error states (A-09).

---

### A-08: Loading state component

**Goal**: Implement loading indicators per DESIGN-STANDARDS §8 for every view that fetches or computes data.

**Why**: Missing loading states make the app feel broken during waits. Users see "empty" instead of "loading."

**Affected files**: Every view that loads data: SourcesTableView, FilesView, DomainsTableView, EmailView, ActivityView, VersionsView, health checks.

**Depends on**: A-04 (typography for loading text).

**Acceptance criteria**:
- No flash of empty content on app launch — initial load shows a loading indicator
- Source enumeration shows scanning indicator
- Email sync shows per-account progress
- Content search shows "Searching X files…"
- All loading text is descriptive (what's happening), not generic (just a spinner)

**Review artifacts**: Screen recording of app launch sequence. Recording of email account sync.

**Out of scope**: Skeleton/redacted placeholders (optional enhancement).

---

### A-09: Error banner component

**Goal**: Replace the catch-all error string banner with a categorized system per DESIGN-STANDARDS §9.

**Why**: For a trust app, unexplained errors with no recovery path are the opposite of the product promise.

**Affected files**: `MainView` error banner. New error categorization in `ManifoldStore` or a dedicated error handler.

**Depends on**: A-01 (colors), A-05 (animation presets), A-06 (badge component for severity).

**Acceptance criteria**:
- Errors categorized: connection, permission, database, network, validation
- Each category has appropriate banner style, duration, and recovery action
- No raw Swift error strings surface as primary user-facing text
- Non-critical errors auto-dismiss after 10 seconds
- Critical errors persist with explicit dismiss + recovery
- Announced to VoiceOver on appearance

**Review artifacts**: Screenshots of each error category. Screen recording of auto-dismiss behavior.

**Out of scope**: Per-account email sync error indicators (Phase B).

---

### A-10: Accessibility baseline

**Goal**: Systematic accessibility pass across all surfaces per DESIGN-STANDARDS §11.

**Why**: Accessibility is not optional for a polished Mac app. VoiceOver, keyboard, and Dynamic Type are baseline expectations.

**Affected files**: Every interactive view (78+ files). Focus on sheets (ReviewAccessSheet, EmailAccountSetupView), cards, tables, and status indicators.

**Depends on**: A-06 (badge has built-in labels), A-07 (empty states have labels).

**Acceptance criteria**:
- Every interactive control has `.accessibilityLabel` if not already descriptive
- Every status indicator has an `.accessibilityLabel` describing state in words
- Card containers use `.accessibilityElement(children: .contain)` for logical grouping
- Every sheet sets keyboard focus on appearance via `@FocusState` + `.defaultFocus()`
- Tab order verified in ReviewAccessSheet and EmailAccountSetupView
- Every `withAnimation` respects `accessibilityReduceMotion` (via `Anim.none` fallback)
- Dynamic Type: tested at 2 sizes above default — no clipping or overlap
- Color-only signaling: zero instances (per DESIGN-STANDARDS §1.3)

**Review artifacts**: Full VoiceOver walkthrough of Overview, Files, Emails tabs. Keyboard-only walkthrough of ReviewAccessSheet.

**Out of scope**: Full localization (A-11). RTL layout.

---

### A-11: Localization infrastructure

**Goal**: Extract all user-facing strings into `.xcstrings` catalog. Do NOT translate — just prepare the infrastructure.

**Why**: Retrofitting localization late is expensive. String extraction is mechanical now but painful after 100+ surfaces are polished.

**Affected files**: New `.xcstrings` catalog. Every view with hardcoded English strings.

**Depends on**: A-07 (empty state copy finalized), A-09 (error copy finalized).

**Acceptance criteria**:
- `.xcstrings` catalog exists with all user-facing strings
- All string literals use `String(localized:)` or `LocalizedStringKey`
- Layout verified with pseudo-localization (30% longer strings) — no clipping
- No translation provided (English only for v1)

**Review artifacts**: Grep for remaining hardcoded English strings outside of code comments.

**Out of scope**: Actual translation. RTL layout.

---

### A-12: Content design rules document

**Goal**: Write a short style guide (per DESIGN-STANDARDS §10) that's referenced during all Phase B–D copy work.

**Why**: Without shared copy rules, every surface sounds different. One product, one voice.

**Affected files**: This is a document, not code. Lives as part of DESIGN-STANDARDS or as a standalone reference.

**Depends on**: Nothing.

**Acceptance criteria**:
- Voice rules defined (calm, factual, respectful)
- Label conventions documented (from v4.1 Copy Guide)
- Empty state, error, and destructive action copy patterns documented
- Reviewed and approved before Phase B begins

**Review artifacts**: The document itself.

**Out of scope**: Marketing copy, App Store description.

---

## Phase B — Core Surfaces

Polish each major surface using the foundation from Phase A. Items are independent within this phase.

**Phase estimate**: 30–38 hours

---

### B-01: Overview tab polish

**Goal**: Apply design system to Overview. Fix card hover, height matching, CTA visibility, and state transitions.

**Why**: Overview is the landing page. It sets the tone for the entire app.

**Affected files**: `OverviewView`, `AgentPolicyCard`, `WorkBlockBanner`, related components.

**Depends on**: Phase A complete. `Depends: V5.2-P2; delta: hover state, card min-height matching, CTA conditional visibility, transition animation`

**Acceptance criteria**:
- Cards have hover state using `Shadow.cardHover` with `Anim.micro`
- Both agent cards maintain equal minimum height
- "Start Tracked Work Block" CTA hidden when no sources configured
- CTA → banner transition animated without layout jump
- Empty state follows §7 with warm, contextual copy
- Passes DoD matrix (§11)

**Review artifacts**: Before/after screenshots. Screen recording of CTA → banner transition. Keyboard walkthrough.

**Out of scope**: Agent policy card content changes (covered by v5.2).

---

### B-02: Files tab polish

**Goal**: Fix sidebar counts, agent-colored dots, table alignment, file type icons, and sort persistence.

**Why**: Files is the core data surface. Dense information requires precise typography and alignment.

**Affected files**: `FilesSidebar`, `SourcesTableView`, `FilesView`, `VersionDetailView`.

**Depends on**: Phase A complete. `Depends: V5.2-P1/P4/P6; delta: sidebar counts, agent-color dots, right-aligned numerics, SF Symbol for sparkles, sort persistence, version empty state copy`

**Acceptance criteria**:
- Sidebar source dots use focused agent color (not always blue)
- "Recently Modified" and "AI-Touched Files" show counts with `Type.numericCaption`
- Items and Size columns right-aligned with `Type.numericBody`
- "✨" replaced with SF Symbol `sparkles`
- Sort selection persists per source via `@SceneStorage`
- "No Versions" empty state explains when versions appear
- Content search results use list layout (not horizontal scroll) for >5 results
- Passes DoD matrix

**Review artifacts**: Before/after screenshots of sidebar, table, and version detail. Dark mode screenshots.

**Out of scope**: File type-specific icons (Phase C). DiffView syntax highlighting (Phase D). Word-level diff (Phase D).

---

### B-03: Emails tab polish

**Goal**: Fix category icons, section counts, sensitivity animation, reading pane empty state, "Cowork" naming, and search token consistency.

**Why**: Emails is complex and information-dense. Inconsistencies are highly visible here.

**Affected files**: `EmailSidebar`, `DomainsTableView`, `EmailView`, `EmailReadingPane`, `EmailSearchField`, `SelectionActionBar`.

**Depends on**: Phase A complete. `Depends: V5.2-P5/P6; delta: SF Symbol category icons, section counts, sensitivity row animation, reading pane empty state, "Cowork"→agent naming, search token styling, plain text monospace`

**Acceptance criteria**:
- Category icons use SF Symbols (building.2, gearshape.2, person, eye.slash) not emoji
- Section headers show domain counts
- Sensitivity change animates rows between sections with `Anim.structural`
- Reading pane empty state: "Select a message to read it here" with `envelope.open` icon
- "Share with Cowork" → "Share with Claude" / "Share with Codex" based on agent focus
- Search tokens use same capsule design as `Badge` component
- Plain text emails render in monospace
- HTML emails block remote images by default with "Load Remote Images" button
- Passes DoD matrix

**Review artifacts**: Before/after screenshots. Screen recording of sensitivity change animation.

**Out of scope**: Domain favicons (Phase C — requires privacy review). Email density toggle (non-goal). Email reply/forward (non-goal).

---

### B-04: Settings polish

**Goal**: Fill gaps in General settings, add connection test to AI Apps, add sync status to Mail, improve Storage explanations.

**Why**: Settings are sparse. 22 lines for General communicates "placeholder."

**Affected files**: `GeneralSettingsPane`, `AIAppsSettingsPane`, `MailSettingsPane`, `StorageSettingsPane`.

**Depends on**: Phase A complete.

**Acceptance criteria**:
- General: Default agent focus picker, keyboard shortcuts reference, menu bar toggle, data & privacy link
- AI Apps: "Test Connection" button per agent, "Last connected" timestamp, MCP config path accessible
- Mail: Sync status per account ("Last synced: 2 min ago"), reorderable accounts
- Storage: "Clean Up" explains what it does before action, "Verify Database" shows clear result badge
- Version number in About window, not settings footer
- Passes DoD matrix

**Review artifacts**: Before/after screenshots of each settings pane.

**Out of scope**: Update checking (requires Sparkle integration). Full account detail inline expansion.

---

### B-05: Onboarding polish

**Goal**: Improve step indicator, welcome copy, progress feedback, skip prominence, and completion state.

**Why**: Onboarding is the first experience. It must communicate competence and care.

**Affected files**: `SetupAssistantView` and sub-views (347 lines total).

**Depends on**: A-02 (app icon for welcome screen), A-07 (empty state patterns), A-12 (copy rules).

**Acceptance criteria**:
- Step indicator: filled circles connected by lines with labels, not plain dots
- Welcome screen: one-sentence product explanation ("Control what AI can see on your Mac"), not "Welcome to Manifold"
- Connect Apps: MCP install shows progress text, errors inline with retry, skip less prominent than continue
- Add Data: added sources listed with remove buttons, email marked as optional
- Review & Finish: shows configured items with checkmarks AND skipped items with neutral indicators, button says "Get Started"
- Window close behavior: re-appears on next launch unless step 2+ completed. Uses `@AppStorage("hasCompletedOnboarding")`
- Transitions respect `accessibilityReduceMotion`
- Passes DoD matrix

**Review artifacts**: Screen recording of full onboarding flow. Dark mode screenshots of each step.

**Out of scope**: Animated icon entrance (nice-to-have, not required).

---

### B-06: About window

**Goal**: Create a custom About window.

**Why**: Every polished Mac app has one. It communicates care in a surface users check occasionally.

**Affected files**: New `AboutView`. `ManifoldApp.swift` to register.

**Depends on**: A-02 (app icon).

**Acceptance criteria**:
- Shows: app icon at ~64pt, "Manifold", version + build number, copyright line, tagline
- Links: website, privacy policy, acknowledgements
- Small and calm — not a marketing page

**Review artifacts**: Screenshot in light and dark mode.

**Out of scope**: Credits scroll or easter eggs.

---

### B-07: Window restoration

**Goal**: Implement `@SceneStorage` for all persistent UI state.

**Why**: Users expect relaunch to restore exactly what they left. This is a baseline macOS convention.

**Affected files**: `ManifoldApp.swift`, `MainView`, `FilesSidebar`, `EmailSidebar`, inspector views.

**Depends on**: Nothing in Phase A specifically, but easier to verify after surfaces are polished.

**Acceptance criteria**:
- Persisted: selected tab, sidebar selection per tab, inspector visibility, agent focus, window position/size
- Relaunch test: close app, relaunch, verify everything matches

**Review artifacts**: Screen recording of close → relaunch cycle.

**Out of scope**: Multiple window support (non-goal).

---

### B-08: EmailAccountSetupView overhaul

**Goal**: Polish the app's most complex modal (838 lines) — step indicator, timeouts, credential UX, error specificity, keyboard focus.

**Why**: Account setup is a critical first-use flow. Generic errors and poor keyboard flow create friction.

**Affected files**: `EmailAccountSetupView` and sub-views.

**Depends on**: A-05 (animation presets), A-09 (error patterns), A-12 (copy rules).

**Acceptance criteria**:
- Step indicator with labels: "Email → Provider → Credentials → Connect → Done"
- Auto-detect timeout at 5 seconds with manual override
- Password field has show/hide toggle
- Connection steps show estimated times for long operations
- Error messages are specific and actionable (e.g., "Gmail requires an App Password if 2FA is enabled")
- OAuth buttons use provider brand colors/icons per guidelines
- Email TextField auto-focused on sheet appear
- Tab cycles through fields in order
- Back button preserves entered data at every step
- Passes DoD matrix

**Review artifacts**: Screen recording of full setup flow with intentional error. Keyboard-only walkthrough.

**Out of scope**: New email providers.

---

### B-09: Sheets and modals consistency

**Goal**: Polish ReviewAccessSheet, ReviewChangesSheet, ShareWithCoworkSheet per audit findings.

**Why**: Sheets are where trust decisions happen. They must feel solid.

**Affected files**: `ReviewAccessSheet`, `ReviewChangesSheet`, `ShareWithCoworkSheet`.

**Depends on**: Phase A complete. `Depends: V5.2-P3; delta: tab crossfade, checkbox entrance animation, footer sticky verification, section collapse, promote progress, success confirmation, agent naming`

**Acceptance criteria**:
- ReviewAccessSheet: Files ↔ Emails tab crossfade, checkbox → "What's Changing" entrance animation, footer sticky with 20+ items
- ReviewChangesSheet: collapsible sections, promote progress bar, brief success state before dismiss
- ShareWithCoworkSheet: "Share with Claude/Codex" naming, agent picker if both connected, success feedback before dismiss
- Enter activates primary CTA, Escape cancels, in all sheets
- Passes DoD matrix

**Review artifacts**: Screen recording of each sheet with keyboard interaction.

**Out of scope**: ReviewAccessSheet content/logic changes (v5.2).

---

### B-10: Trust and privacy UX

**Goal**: Add the trust/privacy layer that's currently missing — data locality messaging, "why am I seeing this?" explanations, destructive action clarity, remote image blocking.

**Why**: Trust is the product. The app controls AI access but doesn't communicate why users should trust Manifold itself.

**Affected files**: Multiple surfaces. New explanatory content in Overview, Settings (Data & Privacy), source removal confirmation, file access indicators. `HTMLEmailView` for remote image blocking.

**Depends on**: A-07 (empty state component for explanatory states), A-12 (copy rules for trust messaging).

**Acceptance criteria**:
- Data locality statement accessible from Settings → Data & Privacy: "All data stays on your Mac. Manifold never sends your files or emails to any server."
- File access indicators have tooltip or popover explaining which policy granted access and when
- Source removal dialog states consequences: what agents lose access to, what happens to version history
- HTML email remote images blocked by default with "Load Remote Images" banner
- "Clean Up Storage" explains what will be removed before action
- Storage retention visible per category in Settings

**Review artifacts**: Screenshots of each trust touchpoint. Copy review document.

**Out of scope**: Full audit trail redesign (future). PDF export of access report (non-goal).

---

## Phase C — Native Feel

System-level integration and platform conventions that make Manifold feel like it belongs on macOS.

**Phase estimate**: 20–26 hours

---

### C-01: Menu bar and command audit

**Goal**: Audit and complete all standard macOS menus (App, File, Edit, View, Window, Help). Ensure every keyboard shortcut appears in a menu.

**Why**: Incomplete menus are immediately noticeable to power users and VoiceOver users. Shortcuts invisible in menus are undiscoverable.

**Affected files**: `ManifoldApp.swift` (`.commands` modifier), any `CommandGroup` / `CommandMenu` definitions.

**Depends on**: Nothing.

**Acceptance criteria**:
- File menu: "Add Folder…", "Add Email Account…"
- Edit menu: standard text commands work in all text fields, Undo reflects app-level undo
- View menu: "Toggle Sidebar", tab switching, "Show Inspector" if applicable
- Window menu: standard items (Minimize, Zoom, Bring All to Front, main window access)
- Help menu: "Manifold Help" (opens website or help book), system search field
- Every keyboard shortcut in the app appears in a menu item
- Access menu commands (⌘⇧R, ⌘⇧W, ⌘⇧P) visible in menus

**Review artifacts**: Screenshot of every menu expanded.

**Out of scope**: Custom menu item icons. Services menu integration.

---

### C-02: Context menus on all rows

**Goal**: Add context menus per DESIGN-STANDARDS §12 to every list/table row.

**Why**: Right-click is a primary macOS interaction. Missing context menus feel incomplete.

**Affected files**: `SourcesTableView`, `FilesView`, `DomainsTableView`, `EmailMessageRow`, `FilesSidebar`, `EmailSidebar`.

**Depends on**: Nothing.

**Acceptance criteria**:
- Every row type has the minimum context menu items per DESIGN-STANDARDS §12
- "Share with [Agent]" reflects the currently focused agent
- All context menu actions work correctly
- VoiceOver: context menu accessible via keyboard (VO+Shift+M)

**Review artifacts**: Screenshot of every context menu.

**Out of scope**: Custom context menu icons.

---

### C-03: Drag and drop

**Goal**: Implement drag and drop per DESIGN-STANDARDS §14.

**Why**: Drag and drop is a foundational macOS interaction. Conspicuously absent in a file-management-adjacent app.

**Affected files**: `FilesSidebar` (drop target), `FilesView` (drag source), related views.

**Depends on**: B-09 (Review sheet must handle pre-selected folder for Finder → sidebar drop).

**Acceptance criteria**:
- Drag folder from Finder → Files sidebar opens Review sheet with folder pre-selected
- Drag file row → Finder reveals file
- Drop target highlighting with `Anim.micro` feedback
- `.onDrop(of: [.fileURL])` registered on sidebar

**Review artifacts**: Screen recording of both drag directions.

**Out of scope**: Drag to reorder sidebar items. Drag .eml files.

---

### C-04: Keyboard polish

**Goal**: Verify and fix keyboard navigation, focus management, and first responder behavior across all surfaces.

**Why**: Keyboard-only users (power users and accessibility users) must be able to do everything without a mouse.

**Affected files**: All major views, especially sheets and complex layouts.

**Depends on**: A-10 (accessibility baseline sets focus on sheet appear).

**Acceptance criteria**:
- Tab order logical in every view — left-to-right, top-to-bottom
- Escape priority: command palette > sheet > popover > (nothing)
- ⌘W closes window but keeps app running (menu bar accessible)
- Focus ring visible on every focused element
- j/k navigation in email (already exists — verify still works)
- Space to scroll reading pane, Enter to focus reading pane
- Full keyboard walkthrough: open app, navigate all tabs, open and dismiss sheets, switch agent focus, all without mouse

**Review artifacts**: Screen recording of full keyboard walkthrough.

**Out of scope**: Vim-style navigation in file browser.

---

### C-05: Full screen and layout edge cases

**Goal**: Verify full screen, split screen, notch, and minimum width behavior.

**Why**: These are invisible baseline expectations. Users notice when they break.

**Affected files**: No code changes expected — this is a verification and fix pass.

**Depends on**: Phase B complete (surfaces must be polished before edge-case testing).

**Acceptance criteria**:
- Full screen: sidebar visible and functional, menu bar extra accessible
- Split screen: works alongside Safari/Terminal (common developer workflow)
- Notch: menu bar icon accessible from overflow area on MacBook Pro
- Minimum width (780pt): no clipping, no overlap, no horizontal scroll
- ⌘N prevented from creating duplicate windows (singleton behavior)
- All verified in both light and dark mode

**Review artifacts**: Screenshots of full screen, split screen, and minimum width.

**Out of scope**: iPad/Catalyst (macOS only).

---

### C-06: Undo system unification

**Goal**: Unify undo toasts per DESIGN-STANDARDS §13. Add ⌘Z support via UndoManager.

**Why**: Inconsistent undo behavior across views feels fragmented.

**Affected files**: `SourcesTableView`, `DomainsTableView`, `ManifoldStore` (new global undo stack).

**Depends on**: A-05 (animation presets for toast).

**Acceptance criteria**:
- Toast design consistent everywhere — same width, position, animation, font
- Toast stacking: new replaces previous
- Toast announced to VoiceOver
- ⌘Z triggers undo for last narrowing action (source removal, domain removal)

**Review artifacts**: Screen recording of two rapid undo actions (verify no stacking).

**Out of scope**: Undo for broadening actions (those go through Review sheet, which is the confirmation).

---

### C-07: Proxy icon and title bar

**Goal**: When a source is selected in Files, show the source name in the window title with a draggable proxy icon.

**Why**: Deeply native. Every document-based Mac app does this. Subtle but noticeable.

**Affected files**: `MainView` or window configuration. `ManifoldApp.swift`.

**Depends on**: Nothing.

**Acceptance criteria**:
- Overview tab: title shows "Manifold"
- Files tab with source selected: title shows source name, proxy icon is draggable to Finder
- Emails tab: title shows "Manifold — Mail" or similar
- Title renders correctly with Liquid Glass toolbar on macOS 26

**Review artifacts**: Screenshot of title bar in each state. Demo of proxy icon drag.

**Out of scope**: Multiple windows.

---

## Phase D — Delight / Later

Items that differentiate "great" from "excellent." All are independent. Implement in any order as time allows.

**Phase estimate**: 18–24 hours

---

### D-01: DiffView upgrades

**Goal**: Add syntax highlighting for known file types and word-level diff highlighting within changed lines.

**Why**: This is what makes Kaleidoscope and Tower feel professional. Currently diffs are line-level with no syntax awareness.

**Affected files**: `DiffView`.

**Depends on**: Nothing.

**Acceptance criteria**:
- Syntax highlighting for Swift, TypeScript, JSON, YAML, Markdown (at minimum)
- Word-level diff: within changed lines, highlight specific changed words/tokens
- Dynamic line number width (no truncation at 1000+ lines)
- "Copy Diff" button producing unified diff format
- Performance: lazy rendering for 5000+ line diffs

**Review artifacts**: Screenshots of highlighted Swift diff and word-level diff.

**Out of scope**: Side-by-side diff mode. Inline editing.

---

### D-02: Command palette improvements

**Goal**: Add fuzzy matching, recent commands, icons, and result count.

**Why**: The command palette is a power user surface. Fuzzy matching and recents make it feel professional.

**Affected files**: `CommandPaletteView`.

**Depends on**: Nothing.

**Acceptance criteria**:
- Fuzzy matching: "rev" matches "Review Access"
- 3 most recently used commands shown when search field is empty
- Each command has an SF Symbol icon
- "X results" label below search field when filtered
- Escape takes priority over all other dismiss actions

**Review artifacts**: Screen recording of fuzzy search and recent commands.

**Out of scope**: Plugin/extension commands.

---

### D-03: Domain favicons (privacy-safe)

**Goal**: Show domain favicons next to "@domain" in DomainsTableView, without leaking domain information to third parties.

**Why**: Significant visual quality upgrade. But must not contradict the trust promise.

**Affected files**: `DomainsTableView`, new favicon cache.

**Depends on**: B-10 (trust/privacy UX established).

**Acceptance criteria**:
- Favicons fetched directly from `https://domain.com/favicon.ico` — NOT via Google's endpoint
- Fetch is opt-in or clearly disclosed in Settings → Privacy
- Favicons cached locally, fetched at most once per domain
- Fallback: generic globe SF Symbol
- No favicon fetch happens without user awareness

**Review artifacts**: Screenshot of domains table with favicons. Privacy disclosure in Settings.

**Out of scope**: High-resolution favicons. Touch icon variants.

---

### D-04: File type-specific icons

**Goal**: Replace generic `doc` icon in FilesView with type-specific icons using `NSWorkspace.shared.icon(forFileType:)`.

**Why**: Makes the file browser feel native and information-rich at a glance.

**Affected files**: `FilesView` file rows.

**Depends on**: Nothing.

**Acceptance criteria**:
- Each file shows its OS-native file type icon (Swift files → Xcode icon, images → Preview icon, etc.)
- Fallback for unknown types: generic document icon
- Icons rendered at consistent size, not blurry at @2x

**Review artifacts**: Screenshot of file list with mixed file types.

**Out of scope**: Custom Manifold-specific file type icons.

---

### D-05: Email search token colors

**Goal**: Color-code search tokens by type for faster visual scanning.

**Why**: Subtle but helpful differentiation in a search-heavy surface.

**Affected files**: `EmailSearchField`.

**Depends on**: A-06 (badge component — tokens should use same capsule language).

**Acceptance criteria**:
- "from:" tokens use agent blue
- "to:" tokens use green
- Date range tokens use orange
- All tokens use `Badge` component styling

**Review artifacts**: Screenshot of multi-token search.

**Out of scope**: New search operators.

---

### D-06: Performance edge case testing

**Goal**: Test and fix performance at scale per audit §7.5.

**Why**: The app must remain responsive with real-world data volumes.

**Affected files**: Various — depends on findings.

**Depends on**: Phase B complete (surfaces must be final before stress testing).

**Acceptance criteria**:
- 100+ sources: SourcesTableView scrolls smoothly, footer totals compute efficiently
- 10,000+ emails: DomainsTableView aggregation doesn't lag UI
- 50+ smart mailboxes: EmailSidebar handles gracefully
- 5000-line diff: DiffView uses lazy loading
- Deeply nested paths: `.truncationMode(.middle)` everywhere

**Review artifacts**: Test results document with specific metrics.

**Out of scope**: Benchmark infrastructure.

---

### D-07: Export capabilities

**Goal**: Verify audit log export quality. Add "Export Current Policy" for compliance.

**Why**: Enterprise users need documentation of access state. Clean exports communicate professionalism.

**Affected files**: `ActivityView` export, new policy export.

**Depends on**: Nothing.

**Acceptance criteria**:
- Activity export produces clean, well-formatted CSV or JSON
- "Export Current Policy" produces human-readable summary: agent names, allowed sources, allowed domains, sensitivity, work block history
- Export uses standard macOS save panel with sensible defaults

**Review artifacts**: Sample export files.

**Out of scope**: PDF report generation (non-goal for v1).

---

## Estimate Summary

| Phase | Scope | Estimate | Notes |
|-------|-------|----------|-------|
| A — Foundation | 12 items | 28–35 hours | Includes design, implementation, QA. Icons may need iteration |
| B — Core Surfaces | 10 items | 30–38 hours | Highest variability — EmailAccountSetupView and trust UX are complex |
| C — Native Feel | 7 items | 20–26 hours | Menu audit and keyboard polish are thorough but mechanical |
| D — Delight | 7 items | 18–24 hours | All optional. Prioritize D-01 and D-03 if time-constrained |
| **Total** | **36 items** | **96–123 hours** | |

Combined with v5.2 (~24.5h) and menu bar (~34h): **~155–182 hours total** from current state to ADA quality.

The range accounts for: design iteration on icons, copy refinement across surfaces, accessibility QA passes, regression testing, and the inevitable discoveries during implementation. The lower bound assumes clean execution with no surprises. The upper bound assumes normal iteration.

---

## How to hand this to Claude Code

1. Implement Phase A items A-01 through A-12 in order (some can parallel — noted in dependencies)
2. After Phase A, hand it DESIGN-STANDARDS.md as a persistent reference
3. Implement Phase B items in any order, but verify each against the DoD matrix before marking complete
4. Implement Phase C items in any order
5. Phase D items are independent — implement as time allows, prioritize D-01 and D-03
6. For every phase, produce the review artifacts listed in each item and in DESIGN-STANDARDS §11.6
