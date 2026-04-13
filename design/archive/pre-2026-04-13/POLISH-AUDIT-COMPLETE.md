# Manifold — Complete Polish Audit

> **Purpose**: Every UI surface, micro-interaction, and visual detail that needs work to bring Manifold from "functional prototype" to "Apple Design Award contender." This is the list you hand to Claude Code after v5.2 and the menu bar spec are implemented. Nothing here contradicts those plans — this is everything *else*.
>
> **Benchmark**: Pixelmator Pro, Things 3, Bear, Craft, Fantastical — apps where every pixel communicates care.
>
> **Inventory**: 78+ SwiftUI view files, 10 components, 4 settings panes, 1 onboarding wizard, 1 menu bar extra, 0 custom assets.
>
> **Organization**: App Identity → Window Shell → Tab-by-Tab → Component-by-Component → Sheets & Modals → Settings → Onboarding → Menu Bar → Cross-Cutting Concerns.

---

## 1. APP IDENTITY

### 1.1 App Icon — Does Not Exist

**Current state**: Manifold has no custom app icon. It uses `shield.checkered` (an SF Symbol) rendered by the system. The Dock shows a generic SwiftUI app icon. This is the single most visible "this is a prototype" signal.

**What needs to happen**:

- **Design a proper macOS app icon** at 1024×1024, rendered at 16/32/64/128/256/512/1024pt
- The icon must work at 16×16 in the Dock's minimized state and at 1024×1024 in the App Store
- Create an `.xcassets/AppIcon.appiconset` with all required sizes
- The icon concept should communicate: protection, visibility, trust. A shield motif is appropriate but it needs to be *Manifold's* shield, not a system glyph
- Consider the macOS 26 icon environment — rounded rectangle superellipse, depth, material. Study Pixelmator Pro's icon (layered, dimensional, communicates the app's purpose at a glance)
- The icon should look correct on both light and dark desktop backgrounds
- Test at 16px in the Finder sidebar and Dock — if the concept doesn't read at that size, simplify

**Deliverable**: `AppIcon.appiconset` with all sizes, plus a 1024×1024 master for App Store

### 1.2 Menu Bar Icon — Needs Custom Glyph

**Current state**: Uses `shield.checkered` / `shield.checkered.fill` SF Symbols. These are fine for development but too generic for shipping.

**What needs to happen**:

- Design a **monochrome template image** that reads as "Manifold" at 18×18pt (36×36px @2x)
- Must work as a macOS menu bar template image (single color, system manages tint)
- Should be recognizable even among 15+ other menu bar icons
- Create `MenuBarIcon.imageset` in the asset catalog with 1x and 2x variants
- Consider a simplified version of the app icon glyph — a stylized M-shield, or the shield outline alone

### 1.3 About Window

**Current state**: No custom About window. macOS shows a generic "About Manifold" with no icon, no credits, no version beyond the Info.plist entry.

**What needs to happen**:

- At minimum: the app icon, "Manifold", version + build number, copyright, and a brief tagline
- Consider a tasteful About window like Bear's or Things 3's — small, calm, shows the icon prominently
- Link to website, acknowledgements, and privacy policy
- The version string currently lives only in `StorageSettingsPane` as a footer — it should be in the About window and optionally in the Settings footer

### 1.4 Asset Catalog — Does Not Exist

**Current state**: No `.xcassets` directory at all. No color sets, no image sets, no data assets.

**What needs to happen**:

- Create `Assets.xcassets` with:
  - `AppIcon.appiconset`
  - `AccentColor.colorset` (the app's brand color — currently blue, but should be an intentional choice)
  - Agent color sets: `ClaudeBlue.colorset`, `CodexPurple.colorset` — so they're defined once, not scattered as `.blue` / `.purple` literals across 40+ files
  - Semantic status colors: `StatusActive.colorset`, `StatusPaused.colorset`, `StatusWarning.colorset`, `StatusDanger.colorset`
  - Menu bar template image
  - Any future custom icons or illustrations

### 1.5 Document Type / UTI Registration

**Current state**: Manifold doesn't register any document types or UTIs.

**What to consider**:

- If Manifold ever exports audit reports, policy snapshots, or review summaries, it should register a `.manifold` document type
- Not critical for v1 but worth a placeholder in the project structure

---

## 2. WINDOW SHELL & CHROME

### 2.1 Window Toolbar

**Covered by v5.2 Phase 1** (global/local toolbar separation). Beyond that:

- **Toolbar customization**: Consider enabling `.toolbar { ... }.toolbarRole(.editor)` or similar so power users can customize toolbar items (macOS standard feature)
- **Toolbar item tooltips**: Every toolbar button should have a `.help("...")` modifier. Currently only `ReadingPaneToolbar` has tooltips. Missing on: AgentFocusControl, search fields, Add Folder, connection indicators
- **Toolbar spacing**: When the window is narrow (780pt minimum), verify that toolbar items don't overlap or clip. Test at minimum width with all controls visible

### 2.2 Window Restoration

**Current state**: Unknown whether the app restores its window position, selected tab, sidebar selection, and inspector state on relaunch.

**What needs to happen**:

- Use `@SceneStorage` for: selected tab, sidebar selection per tab, inspector visibility, agent focus selection
- The user should relaunch Manifold and see exactly what they left. This is a baseline macOS expectation (Finder, Mail, Xcode all do it)

### 2.3 Window Title Bar

**Covered by v5.2 Phase 10** (window title consistency). Additional notes:

- The app name "Manifold" should appear in the proxy icon / title area on Overview. Verify this renders correctly with Liquid Glass toolbar chrome on macOS 26
- When a source is selected in Files, the window title should show the source name — and ideally support the proxy icon (draggable document representation). This is what makes native apps feel native

### 2.4 Full Screen Support

**Current state**: Unknown.

**What needs to happen**:

- Verify the app works correctly in full screen mode
- The sidebar should remain functional (not hidden behind a gesture)
- The menu bar extra should remain accessible from the menu bar in full screen
- Test split-screen with another app (Safari, Terminal) — common developer workflow

### 2.5 Multiple Windows

**Current state**: Uses `WindowGroup(id: "main")` which may or may not support multiple windows.

**What needs to happen**:

- Decide: should Manifold support multiple windows? (Probably not — it's a singleton control surface)
- If not, use `.handlesExternalEvents(matching: Set(["main"]))` to prevent duplicate windows
- Ensure ⌘N doesn't create a second window (or does something useful like opening Settings)

---

## 3. OVERVIEW TAB

### 3.1 Agent Policy Cards

**Mostly covered by v5.2 Phase 2.** Additional polish:

- **Hover state**: Cards should have a subtle hover effect (shadow lift or border brightening) to signal interactivity
- **Card transition on state change**: When access is paused/resumed, the card's opacity and border transition should use `.snappy` animation, not an instant cut
- **Numeric transitions**: The `contentTransition(.numericText())` is already on counts — verify it animates smoothly when sources are added/removed in real time
- **Truncation**: If the agent name is very long (e.g., a custom agent name in the future), the header row should handle it with `.lineLimit(1)` and `.truncationMode(.tail)`
- **Card minimum height**: Both cards should have the same minimum height even if one has fewer summary lines (e.g., Claude has email access, Codex doesn't). Mismatched card heights look broken

### 3.2 Empty State

**Current state**: `ContentUnavailableView` with antenna icon and "Open Settings" button.

**What needs to happen**:

- The empty state should feel *inviting*, not dead. Study Bear's empty state or Things 3's "nothing here" treatment
- Consider a brief illustration or the app icon rendered at ~80pt with a welcoming message
- The copy should explain *why* nothing is here and *what to do*: "Connect Claude or Codex to start monitoring AI access. Once connected, you'll see a summary of what each agent can access."
- If at least one agent is configured but not connected, show a different message: "Waiting for Claude to connect…" with a subtle pulsing indicator
- If both agents are connected but have no access policy, show: "Claude is connected but can't access any files. [Review & Update Access] to get started." (This is in v4.1 spec — verify it's implemented)

### 3.3 "Start Tracked Work Block" CTA

**Covered by v5.2 Phase 2.6.** Additional polish:

- The CTA should not appear when no sources are configured (it's meaningless to track changes on zero files)
- When a work block IS active, the CTA disappears and the global banner takes over — verify this transition is smooth, not a layout jump
- Consider a gentle `.spring` entrance animation when the user first sees the CTA (after connecting and adding sources)

---

## 4. FILES TAB

### 4.1 FilesSidebar (66 lines)

- **Source dots**: The sidebar shows blue/gray dots next to sources. These should use the focused agent's color (blue for Claude, purple for Codex) per v4.1 spec, not always blue
- **Add Folder button**: Currently uses `plus` icon with `.secondary` color. Should be `folder.badge.plus` per v5.2. Make it the last item in the Sources section, not a floating button
- **Sidebar section headers**: "Sources" and "Versions" — these should use `.headerProminence(.increased)` for visual weight
- **Sidebar counts**: "Recently Modified" and "AI-Touched Files" should show counts (e.g., `[12]` and `[8]`) in `.monospacedDigit` font, aligned to the trailing edge. Currently no counts are shown
- **Drag and drop**: Users should be able to drag a folder from Finder into the sidebar to add it as a source. Register the sidebar List for `.onDrop(of: [.fileURL])`. This opens the Review sheet with the dropped folder pre-selected
- **Sidebar minimum width**: v5.2 changes to `min: 220` — verify "Smart Mailboxes" and long source names don't truncate at this width. Consider `.truncationMode(.middle)` for paths

### 4.2 SourcesTableView (253 lines)

- **Table column alignment**: Verify the "Items" and "Size" columns are right-aligned (numeric data should always be right-aligned in tables)
- **Table header styling**: Column headers should use `.font(.caption.weight(.medium))` for readability
- **Row hover state**: Rows should have a subtle highlight on hover. Native `Table` provides this, but if using `List`, add `.listRowSeparator(.visible)` and verify hover
- **Sorting**: The table should support click-to-sort on column headers (Name, Path, Items, Size). If using `Table`, this is native. If using `List`, implement sort descriptors
- **Footer**: v4.1 spec calls for a footer with totals: "3 sources · 247 files · 1.3 GB total / Claude: 225 files (1.2 GB)". Verify this exists
- **Row tinting**: v5.2 Phase 6 covers this (4% agent color opacity on granted rows). Additionally: the tinting should animate in/out when access is toggled, not snap
- **Context menu**: Currently has "Reveal in Finder" and "Remove from Manifold." Add: "View Activity for [source]" (opens Activity drawer filtered to this source), "Copy Path" (puts the path on the clipboard)
- **Remove confirmation**: Removing a source is narrowing (immediate per v4.1), but it's also destructive (all version history for files in that source could be affected). Consider a confirmation dialog or at minimum a more prominent undo toast

### 4.3 FilesView — File Browser (388 lines)

- **Filter bar position**: v5.2 Phase 9.9 flags this — filters must be pinned above the list, not in scrollable content
- **Content search**: The content search feature (searching inside files) shows results in a horizontal scroll of `ContentSearchResultCard` views. This is unusual UX. Consider:
  - Showing results inline in the file list with match highlights
  - Or showing them in a dedicated search results list (like Xcode's Find in Project)
  - The horizontal scroll card pattern doesn't scale past ~5 results
- **File type icons**: Currently uses generic `doc` icon. Consider using file-type-specific SF Symbols: `swift` files → code icon, images → photo icon, markdown → doc.text icon. Or use `NSWorkspace.shared.icon(forFileType:)` for native file type icons
- **AI indicator**: The "●" dot indicating "accessible by focused agent" should use the agent's color and have an `.accessibilityLabel("Accessible by Claude")`
- **Version count**: The "Versions" column shows a count with "✨" for AI-modified files. The sparkle emoji should be replaced with an SF Symbol (`sparkles`) for visual consistency
- **Empty state**: When a source has zero files (empty folder), show a meaningful message: "This folder is empty" with a Reveal in Finder button
- **Loading state**: When switching between sources, there should be a brief loading indicator if file enumeration takes time. Currently unknown if this is handled
- **Sort persistence**: The sort selection (Name/Size/Modified/Type) should persist per source using `@SceneStorage` or `@AppStorage`

### 4.4 VersionDetailView (156 lines)

- **HSplitView divider**: The split between snapshot list and diff panel should have a visible divider. Verify it's draggable and that the user can resize
- **Diff syntax highlighting**: `DiffView` uses green/red background tinting for additions/removals. Consider actual syntax highlighting for known file types (Swift, TypeScript, JSON, etc.) using a lightweight highlighter. This is what makes Kaleidoscope and Tower feel professional
- **Restore button**: Currently conditional on `afterHash` and not-delete. The button should be `.borderedProminent` when available and `.bordered` with `.disabled(true)` when not — so the user knows the action exists even when it's not available
- **Empty state for no versions**: Currently shows "No Versions" ContentUnavailableView. The message should explain: "Manifold tracks file versions during Tracked Work Blocks. Start a work block to begin versioning."
- **Snapshot row interaction**: Clicking a snapshot should feel responsive — consider a brief highlight animation on selection change

---

## 5. EMAILS TAB

### 5.1 EmailSidebar (108 lines)

- **"All Domains" entry**: v5.2 Phase 4 rebuilds the sidebar with "All Mail" at the top (matching v4.1 spec). Verify this is the default selection on launch
- **Account provider icons**: Currently uses manually-mapped provider colors (red=Gmail, blue=Outlook, etc.). These should be defined in the asset catalog as named colors. Consider adding actual provider logos as small template images — but only if licensing allows; otherwise the colored envelope icon is fine
- **Unread count badge**: `UnifiedInboxRow` shows a blue capsule badge for unread count. This is correct Apple Mail behavior. Verify the badge doesn't show when count is 0 (currently conditional)
- **Smart Mailbox section**: Shows `ContentUnavailableView` when empty. This is too heavy — an empty Smart Mailbox section should just show the "New Smart Mailbox" button, not a full empty state graphic
- **Sidebar footer**: Should show "View Activity →" and "Add Account…" consistently. Verify vertical alignment matches FilesSidebar

### 5.2 DomainsTableView (387 lines)

- **Covered by v5.2 Phases 5 and 6** (grouping, "future" text, trust signaling). Additional:
- **Domain favicons**: Consider showing the domain's favicon next to the "@domain" text. This is a significant visual quality upgrade (Mail.app, Spark, and Mimestream all do this). Implementation: fetch favicons from `https://www.google.com/s2/favicons?domain=example.com` and cache them. Fall back to a generic globe icon
- **Category icons**: v4.1 spec shows emoji icons (🏢 🤖 👤 🏦) for domain categories. Replace with SF Symbols for consistency: `building.2` for Work, `gearshape.2` for Automated, `person` for Personal, `eye.slash` for Hidden
- **Domain count in section headers**: Each section header should show the count: "Work (5)" not just "Work"
- **Sensitivity change animation**: When the user changes sensitivity from Moderate to Strict, some domains move from visible to "Hidden by Sensitivity." This transition should be animated — rows should slide from the visible section to the hidden section, not teleport

### 5.3 EmailView — Message Browser (274 lines)

- **Reading pane divider**: The three-pane layout (sidebar/list/detail) should have properly styled dividers. On macOS 26, `NavigationSplitView` with `.balanced` style handles this — verify it looks correct with Liquid Glass
- **Message list density**: Email message rows should support a density toggle (Compact / Default / Relaxed) like Apple Mail. This is a nice-to-have but a strong polish signal
- **Keyboard navigation**: j/k vim-style navigation is already implemented — excellent. Add: Space to scroll the reading pane, Enter to open in new window (or focus reading pane), Delete to move to trash (if applicable), r to reply (future)
- **Multi-select actions**: `SelectionActionBar` shows "Share with Cowork" — this label needs to change per v4.1 agent naming. It should say "Share with Claude" or "Share with Codex" based on the focused agent

### 5.4 EmailReadingPane (89 lines)

- **HTML rendering**: `HTMLEmailView` uses WKWebView with JavaScript disabled. Verify:
  - Dark mode CSS: the injected CSS should respect `@media (prefers-color-scheme: dark)` for proper dark mode email rendering
  - Font scaling: if the user has Accessibility → Display → Larger Text enabled, email text should scale
  - Image loading: currently CID references are resolved. External image loading should be blocked by default with a "Load Remote Images" button (privacy best practice, matches Apple Mail)
- **Plain text rendering**: `PlainTextEmailView` is 13 lines — minimal. Consider using a monospaced font for plain text emails (like Apple Mail does) and wrapping long lines
- **Attachment bar**: `AttachmentBar` shows file cards in a horizontal scroll. Consider:
  - Thumbnail previews for images/PDFs (using QuickLook thumbnails)
  - Double-click to Quick Look preview
  - Drag to Finder to save
- **Empty reading pane**: Shows `ContentUnavailableView("Select an email")`. The icon should be `envelope.open` and the text should be warmer: "Select a message to read it here"

### 5.5 EmailSearchField (149 lines)

- **Token design**: Search tokens use capsule pills with quaternary background. These should use the same capsule design as status badges elsewhere in the app (consistent pill language)
- **Token colors**: Consider color-coding tokens by type: blue for "from:", green for "to:", orange for date ranges. Subtle but helpful
- **Suggestion popup**: The popup should dismiss on Escape, outside click, and when the search field loses focus. Verify all three
- **Search performance indicator**: When searching a large mailbox (10K+ messages), show a progress indicator in the search field or below it

### 5.6 SmartMailboxEditor (239 lines)

- **Condition row layout**: The field/operator/value layout uses fixed-width pickers (100pt each). At narrow window widths, these may compress poorly. Use flexible widths with minimum sizes
- **Add condition animation**: Adding/removing conditions should animate the row in/out with `.spring`
- **Validation feedback**: If the user creates a condition with an empty value field, show inline validation (orange border or helper text) rather than just disabling the Create button
- **Test mailbox preview**: Consider a "Preview" button that shows how many messages match the current conditions before the user saves. This is a power feature that differentiates

---

## 6. COMPONENTS

### 6.1 Spacing.swift — Design Token Gaps

**Current state**: Defines spacing and corner radii. Does NOT define:

- **Shadow presets**: v5.2 mentions `shadow(color: .black.opacity(0.08), radius: 3, y: 1)` for cards. This should be a named token: `Spacing.cardShadow` or a `ViewModifier` like `.cardElevation()`
- **Typography scale**: No typography presets are defined. The app uses ad-hoc `.font(.caption)`, `.font(.callout)`, `.font(.headline)` everywhere. Define a type scale:
  - `Type.title` → `.title2.weight(.semibold)` (section titles)
  - `Type.heading` → `.headline` (card headers, dialog titles)
  - `Type.body` → `.callout` (primary content text)
  - `Type.secondary` → `.callout` + `.foregroundStyle(.secondary)` (supporting text)
  - `Type.caption` → `.caption` (timestamps, counts, badges)
  - `Type.mono` → `.caption.monospaced()` (file paths, code)
- **Opacity scale**: Define named opacities for background tints: `Opacity.rowTint = 0.04`, `Opacity.badgeBackground = 0.12`, `Opacity.disabledContent = 0.5`, `Opacity.scrimOverlay = 0.3`
- **Animation presets**: Define named animations: `Animation.stateChange = .snappy`, `Animation.structural = .spring`, `Animation.entrance = .spring(duration: 0.4)`, `Animation.micro = .spring(duration: 0.2)`

### 6.2 DiffView

- **Line numbers**: Currently shows line numbers at 24pt width. For files with 1000+ lines, this truncates. Use dynamic width based on the maximum line number
- **Word-level diff**: Currently highlights entire lines as added/removed. Consider word-level highlighting within changed lines (green/red backgrounds on the specific changed words). This is what GitHub, Tower, and Kaleidoscope do
- **Copy button**: Add a "Copy Diff" button that copies the diff to the clipboard in standard unified diff format
- **Syntax highlighting**: As mentioned in 4.4, syntax highlighting would significantly elevate the diff view

### 6.3 TimeLabel

- **Relative time formatting**: Currently uses custom relative formatting. v5.2 introduces `ManifoldDateFormatter` with two modes (relative and compact). Migrate TimeLabel to use this shared formatter
- **Live updates**: TimeLabel should update in real time for recent events. "2m ago" should tick to "3m ago" after a minute. Use a `TimelineView(.periodic(every: 60))` wrapper for labels showing events within the last hour
- **Tooltip**: On hover, show the full absolute date+time as a tooltip: "April 11, 2026 at 3:42 PM"

### 6.4 AgentBadge

- **Size variants**: Currently only one size (6pt dot + caption text). Add a `.compact` variant (dot only, no text) for use in tight spaces like table cells, and a `.prominent` variant (10pt dot + callout text) for headers
- **Animation**: The dot color should animate when switching agent focus (blue → purple transition should use `.snappy`)

### 6.5 StatusBadge

- **Consistency audit**: StatusBadge, the state chips in AgentPolicyCard, and the connection badges all use slightly different capsule/pill patterns. Unify into one `Badge` component with variants:
  - `.info` (blue background)
  - `.success` (green background)
  - `.warning` (orange background)
  - `.danger` (red background)
  - `.neutral` (gray/secondary background)
  Each uses the same padding (horizontal: 6, vertical: 2), corner radius (Capsule), font (.caption.weight(.medium)), and opacity (0.12 background, full foreground)

### 6.6 TrackChangesToolbarContent

- **Elapsed time**: Uses `TimelineView` for live updates — good. Verify the timer format matches the Work Block Banner format (both should use the same `ManifoldDateFormatter` or `Text(date, style: .timer)`)
- **Button accessibility**: Add `.accessibilityLabel` and `.accessibilityHint` to Review, Pause, and Stop buttons
- **Compact mode**: At narrow toolbar widths, the full "Tracking · 1h 28m · 12 files" text may be too wide. Consider a compact mode that shows just the colored dot + time, with full details in a popover on click

### 6.7 CommandPaletteView (130 lines)

- **Search behavior**: Commands should be fuzzy-matched (typing "rev" should match "Review Access"). Currently unknown if this is implemented
- **Recent commands**: Show the 3 most recently used commands at the top when the search field is empty (Raycast, VS Code, and Alfred all do this)
- **Command icons**: Each command should have an SF Symbol icon for visual scanning. Currently unknown if icons are present
- **Result count**: Show "X results" in a subtle label below the search field when filtered
- **Animation**: The palette entrance uses `.snappy` — good. The backdrop dim should fade in separately from the palette slide-in (parallax entrance like Spotlight)
- **Escape priority**: Escape should close the palette before closing anything else. Currently implemented in MainView — verify it takes priority over sheet dismissal

### 6.8 LiveCheckRow

- **Progress animation**: When a health check is running, the `ProgressView` should use `.controlSize(.small)` consistently
- **Error recovery**: When a check fails, the "Refresh" button should show a brief success/failure animation after the retry (green flash for success, red shake for failure)
- **Timestamp**: Show "Last checked: 2m ago" in `.caption` below each check row. Currently no feedback on when the check was last run

---

## 7. SHEETS & MODALS

### 7.1 ReviewAccessSheet (296 lines)

- **Covered by v5.2 Phase 3** (verification). Additional:
- **Sheet sizing**: Currently `min: 520×500`. The v4.1 spec calls for full-height attached. Verify this uses `.presentationDetents([.large])` or equivalent for a full-height feel
- **Tab bar animation**: The Files ↔ Emails tab switch inside the sheet should have a smooth crossfade, not a hard cut
- **Checkbox interaction**: Checking a new source in the sheet should visually add it to the "What's Changing" section with an entrance animation (slide in from left with green tint)
- **Footer sticky behavior**: The footer with counts + CTAs must remain pinned to the bottom even when the content scrolls. Verify this works with long source/domain lists (20+ items)
- **Keyboard shortcut**: Enter should activate the primary CTA. Escape should cancel. These should work even when focus is inside the file/email list

### 7.2 ReviewChangesSheet (196 lines)

- **Section collapse**: Applied/Conflicts/New/Skipped sections should be collapsible with disclosure arrows. For large changesets (50+ files), the user needs to focus on conflicts first
- **Conflict resolution**: The conflict section should show both versions (before and after) with a diff preview. Currently unknown if this detail exists
- **Promote progress**: When promoting (writing files back), show a progress bar. Large promote operations can take seconds
- **Success state**: After successful promotion, briefly show a green checkmark confirmation before dismissing — don't just close the sheet instantly

### 7.3 ShareWithCoworkSheet (69 lines)

- **Naming**: "Share with Cowork" → "Share with Claude" / "Share with Codex" based on the focused agent. "Cowork" is an internal codename per v5.2 Phase 9.4
- **Agent picker**: If both agents are connected, add a picker to choose which agent to share with
- **Success feedback**: Currently auto-dismisses on completion. Show a brief success state (checkmark + "Shared") for 1 second before dismissing

### 7.4 EmailAccountSetupView (838 lines)

This is the app's most complex modal at 838 lines. It needs significant polish:

- **Step indicator**: The top progress dots (8pt circles) are too subtle. Use a proper stepped progress indicator with labels: "Email → Provider → Credentials → Connect → Done"
- **Provider detection**: The auto-detect spinner should have a timeout (5 seconds) with a manual override: "Can't detect provider? Choose manually below."
- **Credential field**: The password SecureField should have a "Show/Hide" toggle (eye icon) for verification
- **Connection progress**: The 4-step connection progress (DNS → Connect → Auth → Sync) is good. Add estimated times: "Syncing mailboxes… This may take a minute for large accounts"
- **Error diagnosis**: The failure view shows suggestions — verify these are specific and actionable, not generic. "Check your password" is useless. "Gmail requires an App Password if 2FA is enabled. [Create App Password →]" is useful
- **OAuth flow**: The "Sign in with Microsoft" button should use Microsoft's brand colors and icon per their brand guidelines
- **Back button**: Verify the Back button works correctly from every step and doesn't lose entered data
- **Keyboard focus**: The email TextField should be auto-focused when the sheet appears. Tab should cycle through fields in order

### 7.5 EmailAccountDetailSheet

**Current state**: Opened from EmailView when clicking account details. Shows account info, sync controls, and configuration.

**What needs polish**:

- **Sync controls**: Should show last sync time, next sync time, manual sync button with spinner
- **Storage used**: Show how much local storage this account uses
- **Advanced settings**: IMAP server, port, auth method should be visible in a disclosure group (for troubleshooting)
- **Remove account**: Should be a red destructive button at the bottom with confirmation dialog
- **Sheet sizing**: Should match other settings-type sheets (~460pt wide)

### 7.6 SmartMailboxEditor (239 lines)

- **Covered in 5.6 above.** Additional: consider a template picker for common smart mailboxes: "Unread from Known Senders", "Attachments This Week", "Flagged and Unread"

### 7.6 AddMailAccountSheet (86 lines)

- **Provider button hover**: Each provider button should have a hover state (slightly brighter background)
- **Provider ordering**: Gmail should be first (most common). Current order is already correct
- **"Other IMAP" option**: Should be visually distinguished as a fallback (lighter styling, at the bottom, with a separator)
- **Sheet width**: Currently 460pt — appropriate. Verify it's centered and doesn't shift when opening sub-sheets

---

## 8. SETTINGS

### 8.1 General Settings Pane (22 lines)

**Current state**: 22 lines. Two sections: Launch at Login + Notifications. This is sparse.

**What's missing**:

- **Appearance**: Light / Dark / System toggle (if the app has any custom theming)
- **Default agent focus**: Let the user choose which agent is focused by default (Claude / Codex / Compare)
- **Keyboard shortcuts section**: Show the app's keyboard shortcuts or link to a full list
- **Update checking**: "Automatically check for updates" toggle (if using Sparkle or similar)
- **Data & Privacy**: Link to privacy policy, "Reset All Access Policies" button (with confirmation), "Export Audit Log" button
- **Menu Bar**: Toggle to show/hide the menu bar icon, option for menu bar icon style (if multiple variants exist)

### 8.2 AI Apps Settings Pane (155 lines)

- **Covered by v5.2 Phase 8** (integration cards). Additional:
- **Connection test button**: Each agent card should have a "Test Connection" button that sends a ping through the MCP bridge and shows the round-trip time
- **MCP config path**: Show the path to the MCP config file with a "Reveal in Finder" button and a "Copy" button. Currently hidden in a DisclosureGroup in the Connect sheet — it should be accessible from Settings too
- **Last connected timestamp**: Show "Last connected: 3 hours ago" or "Connected since: 2:14 PM" for each agent

### 8.3 Mail Settings Pane (80 lines)

- **Account order**: Accounts should be reorderable (drag to reorder, or up/down arrows). The order should match the sidebar order
- **Account detail**: Clicking an account should expand or navigate to show: provider, email, IMAP server, last sync time, message count, storage used. Currently this is only in the `EmailAccountDetailSheet` — consider inline expansion
- **Sync status per account**: Show a small sync indicator: "Last synced: 2 min ago" or "Syncing…" with a spinner
- **Remove account**: The context menu has "Remove Account" (destructive). This should have a confirmation dialog: "Remove [email]? This will delete all locally stored messages for this account."

### 8.4 Storage Settings Pane (85 lines)

- **Storage bar**: v5.2 Phase 8.2 adds a proportional bar indicator. Additional: break it down by category (snapshots, email, blobs) with color-coded segments like macOS System Settings → Storage
- **Clean Up explanation**: The "Clean Up Storage" button should explain what it does before the user clicks: "Removes orphaned data and compacts the database. Your files and email are not affected."
- **Database integrity badge**: After "Verify Database," show the result prominently: ✓ OK (green) or ⚠ Issues Found (orange with details)
- **Version number**: Currently shown as a tiny footer. Move to the About window. In Settings, show only build info if useful for support

### 8.5 Settings Window Chrome

- **Tab icons**: Currently uses generic SF Symbols (gearshape, cpu, envelope, externaldrive). Consider more descriptive icons: `gearshape` for General, `cpu.fill` for AI Apps, `envelope.fill` for Mail, `internaldrive.fill` for Storage
- **Settings window size**: The 580×500 minimum is appropriate. Verify that content doesn't overflow when Settings has many accounts or long paths

---

## 9. ONBOARDING (SetupAssistantView, 347 lines)

### 9.1 Welcome Screen

- **Icon**: Uses `shield.checkered` at 56pt — will be the app icon once designed
- **Copy**: Should explain what Manifold does in one sentence. Not "Welcome to Manifold" — that wastes the prime real estate. Try: "Control what AI can see on your Mac."
- **Animation**: Consider a subtle entrance animation for the icon (scale from 0.8 to 1.0 with `.spring`)

### 9.2 Connect Apps Screen

- **Inline agent cards**: These show health checks inline (good — no nested sheets per v4.1). Verify the checks run automatically when the screen appears, not only on button press
- **Skip button**: "Skip" should be less prominent than "Continue" — use `.buttonStyle(.plain)` with `.foregroundStyle(.secondary)`
- **Progress feedback**: When MCP config is being installed, show what's happening: "Adding Manifold to Claude's config…" (not just a spinner)
- **Error handling**: If the MCP install fails, show the error inline with a retry button. Don't silently fail

### 9.3 Add Data Screen

- **Folder picker**: The NSOpenPanel should allow multiple selection and show only directories. Verify it opens at the user's home directory
- **Added sources feedback**: After adding folders, show them in a list with remove buttons (×) so the user can undo before proceeding
- **Email CTA**: The "Add Email" button should explain it's optional: "Add email accounts to monitor what AI can read in your mail. You can do this later from Settings."

### 9.4 Review & Finish Screen

- **Summary**: Show what was configured with green checkmarks. But also show what was *skipped* with neutral indicators — so the user knows they can come back
- **"Open Manifold" vs "Done"**: The button should be "Get Started" (positive, forward-looking) not just "Done" (neutral, closing)
- **Post-onboarding**: After dismissing, the Overview tab should be selected and the main window should be focused

### 9.5 Cross-screen concerns

- **Progress dots**: The 8pt circles are too subtle. Use a proper step indicator: filled circles connected by lines, with labels below each. Study the Apple ID setup flow or Craft's onboarding for good examples
- **Transitions**: Currently uses asymmetric left/right slide. Verify this respects `accessibilityReduceMotion`
- **Window closing**: If the user closes the onboarding window (⌘W), should it reappear on next launch? Probably yes, unless they completed at least step 2 (connected one agent). Use `@AppStorage("hasCompletedOnboarding")` to track

---

## 10. MENU BAR EXTRA

**Covered by MENU-BAR-SPEC.md.** Additional polish notes:

- **Panel dismiss**: Clicking outside the panel should dismiss it (system default for window-style MenuBarExtra). Verify
- **Panel appearance animation**: The system handles this, but verify it doesn't flicker or jump on macOS 26 with Liquid Glass
- **Dark/light mode**: The panel should look correct in both. Agent colors (blue/purple) should maintain sufficient contrast on both backgrounds
- **Keyboard navigation**: Tab should cycle through interactive elements in the panel. Escape should dismiss
- **Screen with notch**: Test on MacBook Pro with notch — if Manifold's menu bar icon is pushed behind the notch, the system hides it in the overflow area. The icon should still be functional when accessed from there

---

## 11. CROSS-CUTTING CONCERNS

### 11.1 Color System

**Current state**: Agent colors are hardcoded as `.blue` and `.purple` literals scattered across 40+ files.

**What needs to happen**:

- Define `Color.claudeBlue` and `Color.codexPurple` as named colors in the asset catalog
- Define all semantic status colors: `.statusActive` (green), `.statusPaused` (orange), `.statusDanger` (red), `.statusInfo` (blue)
- Replace every hardcoded `.blue`, `.purple`, `.green`, `.red`, `.orange` that carries semantic meaning with a named color
- **Dark mode verification**: Every custom color must be tested in both appearances. The 0.04 and 0.12 opacity tints used for row backgrounds and badge fills may need different values in dark mode (light tints are more visible on dark backgrounds)
- **High contrast mode**: Test with Accessibility → Display → Increase Contrast enabled. Capsule badges, row tints, and status dots must remain visible

### 11.2 Typography

**Current state**: Ad-hoc font choices across 78+ files. No type scale defined.

**What needs to happen**:

- Audit every `.font()` call in the codebase for consistency
- Key rules:
  - **Headlines/titles**: `.headline` or `.title3.weight(.semibold)` — never `.title` (too large for a utility app)
  - **Body text**: `.callout` — this is Manifold's base reading size
  - **Supporting text**: `.callout` + `.foregroundStyle(.secondary)`
  - **Captions**: `.caption` — timestamps, counts, badges
  - **Monospaced**: `.caption.monospaced()` — file paths, code, versions, dates
  - **Numeric data**: Always `.monospacedDigit()` — counts, sizes, times
- Verify all `.monospacedDigit()` usage: file counts, email counts, byte sizes, timestamps. Currently some views use it and others don't

### 11.3 Animation & Motion

**Covered by v5.2 Phase 9.** Additional:

- **Preference for springs**: Every `.animation` and `.withAnimation` call should use a named spring preset. Grep for any remaining `.easeInOut`, `.easeIn`, `.easeOut`, `.linear` — these should all be replaced
- **Transition consistency**: Entry transitions should use `.move(edge: .leading)` for forward navigation, `.move(edge: .trailing)` for back navigation, `.opacity` for cross-fade. Currently transitions are inconsistent
- **Micro-animations to add**:
  - Undo toast entrance: slide up from bottom with `.spring`
  - Agent card state change: border/opacity transition with `.snappy`
  - Sidebar selection: background highlight with `.spring(duration: 0.15)`
  - Table row tint change: fade with `.spring(duration: 0.2)`
  - Badge count change: `.contentTransition(.numericText())` everywhere counts appear
  - Error banner: slide down from top with `.spring`, auto-dismiss after 5 seconds with fade

### 11.4 Accessibility

**Current state**: Some views have `accessibilityLabel` and `accessibilityHint`. Many don't.

**Complete accessibility audit**:

- **Every interactive control** (Button, Toggle, Picker, TextField) must have an `.accessibilityLabel` if the label isn't already descriptive
- **Every status indicator** (colored dots, state chips, badges) must have an `.accessibilityLabel` describing the state, not the visual appearance. "Claude is connected and active" not "Blue filled circle"
- **Rotor navigation**: Add `.accessibilityElement(children: .contain)` to card containers so VoiceOver groups them logically
- **Dynamic Type**: Test with large text sizes (Accessibility → Display → Larger Text). Most SwiftUI views handle this automatically, but custom layouts with fixed sizes may break
- **Reduce Motion**: v5.2 Phase 9.6 adds checks. Verify every `withAnimation` and `.animation` block respects this
- **Keyboard focus**: Every sheet should have a focused element on appearance (usually the first text field or the primary button). Use `@FocusState` and `.defaultFocus()`
- **Tab order**: In complex views (ReviewAccessSheet, EmailAccountSetupView), verify Tab moves through controls in reading order
- **Color-only signaling**: No state should be communicated by color alone. Every colored dot must have a text label nearby. The v4.1 spec explicitly requires this

### 11.5 Empty States

**Audit of every empty state in the app**:

| View | Current Empty State | Quality | Improvement |
|------|-------------------|---------|-------------|
| OverviewView | ContentUnavailableView, antenna icon | Functional | Warmer copy, app icon, clear next step |
| SourcesTableView | ContentUnavailableView, "Add Folder" | Good | Explain what sources do |
| FilesView | ContentUnavailableView | Basic | Differentiate "empty folder" from "no sources" |
| DomainsTableView | ContentUnavailableView, no accounts | Functional | Guide to adding email accounts |
| EmailMessageList | MessageListEmpty | Good | Already has conditional messages |
| EmailReadingPane | "Select an email" | Basic | Warmer copy, suggest keyboard shortcuts |
| VersionDetailView | 4 variants (no versions, deleted, no changes, no selection) | Good | "No Versions" needs explanation of when versions appear |
| ActivityView | ContentUnavailableView, conditional on MCP | Good | Explain what triggers activity |
| VersionsView | ContentUnavailableView with storage used | Good | Explain when versions start tracking |
| EmailSidebar SmartMailbox section | ContentUnavailableView | Too heavy | Just show the "New" button |
| Settings Mail | "No email accounts" tertiary text | Minimal | Add an icon and setup CTA |

**General empty state rules**:
- Every empty state should answer three questions: (1) What would be here? (2) Why is it empty? (3) What's the next step?
- Use `ContentUnavailableView` for full-surface empties (entire tab, entire pane)
- Use inline text with a CTA button for section-level empties (empty sidebar section, empty table section)
- Never show a blank white/gray rectangle with no explanation

### 11.6 Loading States

**Current state**: Most loading states use a generic `ProgressView()`. Some views have no loading state at all.

**What needs improvement**:

- **Initial data load**: When Manifold launches and loads policies, sources, and email accounts from SQLite, there should be a brief, graceful loading state — not a flash of empty content followed by data appearing
- **Email sync**: When syncing a new email account (can take 30+ seconds for large mailboxes), show a progress indicator with the account name and approximate progress
- **Source enumeration**: When counting files in a large source folder, show a scanning indicator
- **Content search**: When searching inside files, show a progress bar with "Searching X files…"
- **Health checks**: When running integration health checks, show the spinner per-check (already done in LiveCheckRow — verify it's used everywhere)

### 11.7 Error Handling

**Current state**: The error banner in MainView shows `store.lastError` as a string. This is a catch-all.

**What needs improvement**:

- **Error categorization**: Different errors need different treatment:
  - Connection errors → banner with retry button
  - Permission errors → banner with link to System Settings
  - Database errors → banner with "Restart Manifold" suggestion
  - Network errors (email sync) → subtle indicator per account, not a global banner
- **Error persistence**: Currently errors appear and stay until dismissed. They should auto-dismiss after 10 seconds for non-critical errors, and persist for critical ones
- **Error details**: The banner should have a "Details" disclosure that shows the full error description. The banner headline should be human-readable, not a Swift error string
- **Recovery actions**: Every error should have at least one actionable recovery step, even if it's just "Try again"

### 11.8 Undo System

**Current state**: Undo toasts in SourcesTableView and DomainsTableView with 5-second auto-dismiss. v5.2 Phase 9.8 adds ⌘Z fallback.

**What needs improvement**:

- **Undo toast design**: The toast should be consistent everywhere — same width, same position (bottom-center of the content area), same animation, same font
- **Toast stacking**: If two undo actions happen in quick succession, the second toast should replace the first (not stack or overlap)
- **Toast accessibility**: Announce toast content to VoiceOver: `.accessibilityAnnouncement("Removed Claude access to web-app. Undo available.")`
- **Undo scope**: Currently undo is per-view (sources vs. domains). Consider a global undo stack in `ManifoldStore` that handles the last N undoable actions with ⌘Z

### 11.9 Drag and Drop

**Current state**: No drag and drop support.

**What should be added**:

- **Drag folders into sidebar**: Drop a folder from Finder onto the Files sidebar → opens Review sheet with that folder
- **Drag .eml files into email list**: Drop an .eml file → imports it into the current account
- **Drag source rows to reorder**: Reorder sources in the sidebar by dragging (optional — alphabetical may be fine)
- **Drag file from FilesView to Finder**: Export/reveal the file (system provides this if using proper file representations)

### 11.10 Context Menus

**Audit of all context menus**:

| View | Current Context Menu | Missing |
|------|---------------------|---------|
| SourcesTableView row | Reveal in Finder, Remove | View Activity, Copy Path, Show in Sidebar |
| FilesView file row | Open, Reveal, Copy Path, Version History | Share with Agent |
| DomainsTableView row | (none detected) | View Emails, Copy Domain, View Activity |
| EmailMessageRow | (none detected) | Flag, Share with Agent, Copy Subject, View in Mail |
| AccountTreeSection header | Sync Now, Account Details, Toggle Sync, Remove | — (complete) |
| Sidebar source item | (none detected) | Reveal in Finder, Remove, View Activity |

**Add context menus to every list/table row.** Users expect right-click functionality on macOS. Every item should have at least "Copy" and one navigation action.

### 11.11 Haptics & Sound

**Current state**: No haptic feedback or sound effects.

**What to consider**:

- macOS doesn't have widespread haptic support (MacBook trackpad only), but `NSHapticFeedbackManager` can provide subtle feedback for:
  - Undo toast appearance (`.alignment` pattern)
  - Pause All activation (`.levelChange` pattern)
  - Work block start/finish (`.generic` pattern)
- **No sound effects** unless the user explicitly opts in. Trust apps should be quiet. System notification sounds are sufficient

### 11.12 Localization Readiness

**Current state**: No `.xcstrings` or `.strings` files. All strings are hardcoded in English.

**What needs to happen before 1.0**:

- Extract all user-facing strings into `.xcstrings` catalog
- Use `LocalizedStringKey` or `String(localized:)` for all text
- Verify layout doesn't break with German (30% longer) or Japanese (potentially taller)
- At minimum: prepare the infrastructure even if launching English-only. Retrofitting localization is much harder than planning for it

### 11.13 Performance Edge Cases

- **100+ sources**: Test the SourcesTableView with 100 source folders. Does it scroll smoothly? Is the footer total computed efficiently?
- **10,000+ emails**: Test DomainsTableView computation speed with a 10K-message mailbox. The SQL GROUP BY for domain aggregation runs off the main actor (verified in codebase) — but verify the UI update doesn't lag
- **50+ smart mailboxes**: Test EmailSidebar with many smart mailboxes. The disclosure group should handle this gracefully
- **Large diffs**: Test DiffView with a 5000-line diff. It should use lazy loading (LazyVStack), not render all lines at once
- **Long file paths**: Test with deeply nested paths (~/A/B/C/D/E/F/G/file.txt). Every path display should use `.truncationMode(.middle)` so both the root and the filename are visible

### 11.14 Print / Export

- **Audit log export**: ActivityView has a "Copy Summary" and "Export" button. Verify Export produces a clean, well-formatted file (CSV or JSON)
- **Policy export**: Consider adding "Export Current Policy" that produces a human-readable summary of what each agent can access. Useful for compliance documentation
- **PDF report**: For enterprise users, a "Generate Access Report" feature that produces a PDF with: current policy state, recent activity, change history. This is a future feature, but the architecture should support it

---

## 12. IMPLEMENTATION PRIORITY

After v5.2 and menu bar spec are complete, the polish work should be done in this order:

```
P0 — Ship blockers (without these, the app isn't ready for public use)
├── 1.1  App icon design and asset catalog setup
├── 1.2  Menu bar custom icon
├── 1.4  Asset catalog with named colors (unblocks color consistency)
├── 6.1  Design token completion (shadows, type scale, opacity, animation)
├── 11.1 Color system audit (replace all hardcoded colors)
├── 11.5 Empty state improvement (every surface)
└── 11.4 Accessibility pass (labels, hints, keyboard, VoiceOver)

P1 — First impression (these make users feel the app is polished)
├── 1.3  About window
├── 2.2  Window restoration (@SceneStorage)
├── 9.*  Onboarding polish (progress indicator, copy, animations)
├── 11.2 Typography audit (consistent type scale)
├── 11.3 Animation consistency (springs everywhere, micro-animations)
├── 7.4  EmailAccountSetupView polish (838 lines, most complex modal)
├── 3.2  Overview empty state warmth
└── 11.7 Error handling improvement

P2 — Power user delight (these differentiate from "good" to "great")
├── 4.1  Sidebar drag and drop (folders from Finder)
├── 11.10 Context menus on every row
├── 11.9 Drag and drop support
├── 5.2  Domain favicons
├── 6.2  DiffView syntax highlighting
├── 6.7  Command palette improvements (fuzzy search, recent, icons)
├── 4.3  File type-specific icons
├── 11.8 Unified undo system
└── 11.6 Loading state improvements

P3 — Excellence (these are what Apple Design Award judges notice)
├── 2.3  Proxy icon support in title bar
├── 2.4  Full screen verification
├── 4.4  DiffView word-level highlighting
├── 5.5  Email search token colors
├── 5.6  Smart mailbox template picker
├── 11.12 Localization readiness
├── 11.13 Performance edge case testing
├── 11.14 Export/report capabilities
├── 11.11 Haptic feedback
└── 2.5  Multiple window prevention
```

**Estimated total**: P0 ~20 hours, P1 ~25 hours, P2 ~20 hours, P3 ~15 hours.

Combined with v5.2 (~24.5 hours) and menu bar (~34 hours), the full path from current state to ADA-quality is approximately **140 hours** of implementation work.

---

## 13. THE GAP BETWEEN "GOOD APP" AND "AWARD-WINNING APP"

The v5.2 plan fixes the structural and trust-truthfulness issues. The menu bar spec adds the system integration layer. This document covers the remaining gap — and the honest truth is that the gap is mostly about *consistency and care*, not features.

What Pixelmator Pro, Things 3, and Bear have in common isn't clever features. It's that every surface received the same level of attention. No empty state was left as a placeholder. No icon was left as a generic system glyph. No animation was left as `.easeInOut`. No color was left as a `.blue` literal. No error state was left as a Swift string dump. No accessibility label was left missing.

The app icon alone will change more first impressions than any three code changes combined. The typography consistency will change more *sustained* impressions than any feature. The empty states will change how new users feel about the app in their first 60 seconds.

The work is not glamorous. It's an audit of every `.font()` call, every `.foregroundStyle()`, every `.accessibilityLabel()`, every empty state, every context menu, every edge case. But that's exactly what separates apps that win awards from apps that merely work.
