# Manifold — Visual Fix Decisions

> **What this is**: One definitive fix per issue from VISUAL-CRITIQUE-v1.md. Every choice is grounded in Apple's current HIG guidance, WWDC25 session material (sessions 356, 323, 310, 219, and the design/UI frameworks group labs), and the design standards already defined in DESIGN-STANDARDS.md. Where two options were close, the tiebreaker was always: which one produces a coherent system when combined with every other decision on this page.
>
> **Governing sources**:
> - [WWDC25 Session 356 — Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/): Liquid Glass soft vs hard, scroll edge effects, sidebar/toolbar rules, content hierarchy through layout not decoration
> - [WWDC25 Session 323 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/): NavigationSplitView, toolbar spacing/grouping, search patterns, Liquid Glass adoption in SwiftUI
> - [WWDC25 Session 310 — Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/): macOS-specific hard glass, NSSplitViewController complexity, scroll edge effects for column sorting
> - [WWDC25 Design Group Lab](https://gist.github.com/samhenrigold/2da3acec094ed339a82155583c1ab293): "Glass is a single floating navigation plane — never nest glass on glass." Remove custom toolbar backgrounds. Express hierarchy through layout/grouping/spacing, not color overrides. Monochromatic controls; color only for hero actions and status indicators. macOS prefers text labels over symbols. 30+ new HIG pages this year — priority reads: colors, materials, scroll edge effects, symbols/menus.
> - [WWDC25 UI Frameworks Lab](https://gist.github.com/samhenrigold/7255ed81aed8c41f0b3a7f3dde9d6022): Use NSSplitViewController (or NavigationSplitView) for split views — "a lot of unseen complexity" in scroll edge effects, layering, and fullscreen behaviors. searchable modifier on TabView for morph animation.
> - [Apple HIG — Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars): Sidebar on leading side for section navigation. Now inset with Liquid Glass. Content flows behind.
> - [Apple HIG — Split Views](https://developer.apple.com/design/human-interface-guidelines/split-views): Three-column layout with NavigationSplitView. balanced vs prominentDetail styles. Column widths configurable with min/ideal/max.
> - [Apple HIG — Lists and Tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables): Data in sortable columns. SwiftUI Table for selectable, sortable multi-column data.
> - [Apple HIG — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos): Power, spaciousness, flexibility. In-depth productivity. Multiple apps at once. Dense information is appropriate.
> - [Apple Newsroom — New Design System](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/): Liquid Glass "brings greater focus to content." Controls give way to content. Toolbars float as a distinct layer above content.
> - [ContentUnavailableView docs](https://developer.apple.com/documentation/swiftui/contentunavailableview) + [Antoine van der Lee analysis](https://www.avanderlee.com/swiftui/contentunavailableview-handling-empty-states/): Three view builders (label, description, actions). Standard search variants. Differentiate empty from loading from error.
> - [NavigationSplitView API](https://developer.apple.com/documentation/SwiftUI/NavigationSplitView): Two or three columns. .navigationSplitViewColumnWidth(min:ideal:max:) for macOS column sizing. balanced and prominentDetail styles.
>
> **Design system coherence rule**: Every fix on this page must produce a result that looks like it came from the same designer on the same day. If a fix for one issue would create visual conflict with a fix for another issue, the conflict is resolved here, not downstream.

---

## Decision principles (derived from the sources above)

1. **Content dominates the window.** Every pixel earns its place by showing the user's data or providing a clear path to action. Dead space, placeholder rows, and hedge-language empty states are eliminated.

2. **Glass is a navigation layer, not decoration.** Liquid Glass lives in toolbars, sidebars, and top-level containers. It floats above content. Never nest glass on glass. Never put glass inside scroll views. Use hard glass on macOS for clarity (pinned table headers, interactive text, controls without backgrounds).

3. **Hierarchy through layout, not paint.** Express information hierarchy through grouping, spacing, and typography weight — not through background colors, borders, or overrides. The exception: agent identity colors (ClaudeBlue, CodexPurple) used at defined opacity levels from DESIGN-STANDARDS §3.

4. **Monochromatic controls; color for meaning only.** Toolbar and navigation controls are monochrome by default. Color is reserved for: (a) agent identity, (b) status indicators consistent across the app, (c) hero/preferred actions. Every use of color must pass the color-only prohibition from DESIGN-STANDARDS §1.3.

5. **macOS prefers text labels over symbols.** On the Mac's larger screen, prefer explicit text. Ambiguous actions (edit, select, filter) must be text, not symbols alone. (WWDC25 Design Lab: "symbol tests showed these don't read clearly" for ambiguous actions.)

6. **Standard components over custom.** SwiftUI `Table`, `NavigationSplitView`, `ContentUnavailableView`, `DisclosureGroup`, `.searchable`, `.headerProminence(.increased)` — use the platform's vocabulary. These auto-adopt Liquid Glass, scroll edge effects, accessibility, and future design updates.

7. **Honest state.** A trust app cannot hedge about its own state. If syncing, show progress. If empty, say so definitively. If disconnected, say it plainly. No "or" language, no "may be," no generic icons where specific ones exist.

---

## SCREENSHOT 1: OVERVIEW TAB

---

### 1.1 — Massive dead space below cards

**Decision: Fix A — Vertical expansion (cards become dashboards)**

Make each agent card taller and richer. Show the 3 most recent activity events inline per agent (last file accessed, last email read, timestamp). Show the actual source folder names with access-status dots. The cards fill 60%+ of the viewport and become the dashboard. The user opens Manifold and immediately sees what each agent has been doing.

**Why this fix**: Apple's core design principle from WWDC25 is "content dominates the window." ADA winners fill their primary view with the user's actual data. Fix B (stacked layout) breaks the side-by-side comparison that's natural for two agents. Fix C (GeometryReader/ViewThatFits) is an engineering mechanism, not a design solution — it doesn't solve the question of what content fills the space.

**Why not the others**: Fix B loses the at-a-glance comparison of two agents, which is Manifold's core interaction model. Fix C defers the content decision to the viewport size, which means the narrow-window experience is still thin.

**Compatibility check**: Works with 1.2 (agent color identity adds visual weight to larger cards), 1.4 (CTA integrates into card footer naturally), 1.5 (per-agent controls live on each card).

---

### 1.2 — Agent cards have no visual weight

**Decision: Fix A — Agent color identity**

Each card gets a 4pt left border in the agent color (ClaudeBlue or CodexPurple from asset catalog). Background: agent color at `Opacity.rowTint` (0.04). `Shadow.card` (black 0.08, radius 3, y: 1). The status dot becomes a filled 10pt circle in the agent color, paired with a text badge ("Active" / "Paused") — satisfying the color-only prohibition.

**Why this fix**: This is the Fantastical calendar-color pattern, the most widely validated card identity technique in macOS apps. It uses color for meaning (which agent) while keeping the structure standard. The left border creates instant scannability — your eye can distinguish the two cards without reading text.

**Why not the others**: Fix B (header bar) is more iOS-like — colored header strips feel like UIKit cards, not macOS. Fix C (mini-dashboard grid) is too dense for the overview; we already have rich content from fix 1.1.

**Apple doc basis**: WWDC25 Design Lab: color for "status indicators consistent across the app." Agent identity is a consistent status indicator throughout Manifold.

---

### 1.3 — "20 sessions" is legacy language

**Decision: Fix B — Truthful status subtitle**

Replace the subtitle with the actual runtime state: "Claude + Codex active" or "Claude active · Codex paused" or "Connecting…" The title bar becomes a live status indicator. The format uses agent names (not agent counts) because Manifold has exactly two agents and the user needs to know which one has which state.

**Why this fix**: Decision principle 7 (honest state). The title bar is prime real estate — make it useful. Fix A (remove entirely) wastes it. Fix C (dot in toolbar) is too subtle for the most important status in the app and duplicates X.4.

**Why not the others**: Fix A leaves the title bar carrying zero information when it could carry the single most important fact. Fix C's dot will already exist per X.4 — duplicating it in the title is redundant.

---

### 1.4 — Orphaned "Start Tracked Work Block" CTA

**Decision: Fix A — Integrate into card footer**

Add a "Start Tracked Work Block" row as a shared footer spanning both agent cards. This connects the action to the data. The button appears after the agent summaries, creating a natural "review data → take action" flow. When a work block IS active, this footer becomes a live status bar showing the block's duration and change count.

**Why this fix**: Apple's interaction guidance: actions near their context. A floating CTA with no visual connection to anything is a pattern Apple explicitly discourages in HIG under "Buttons and controls" — controls should appear where the user expects them based on the information flow.

**Why not the others**: Fix B (conditional prominence) adds logic complexity for marginal UX gain. Fix C (separate section) creates yet another section on a page that needs consolidation, not expansion.

---

### 1.5 — Ambiguous unlabeled toggle

**Decision: Fix C — Move controls to agent cards**

Remove the global toggle from the toolbar entirely. Put pause/resume controls on each agent card individually — a text button reading "Pause Access" (or "Resume Access" per DESIGN-STANDARDS §10.2). This matches v4.1's per-agent control model and eliminates the ambiguous global control.

**Why this fix**: WWDC25 Design Lab: "Do you need six buttons? Could you use a menu?" Applied inversely: do you need a global control when the model is per-agent? No. The global toggle is an architecture shortcut that creates UX ambiguity. Per-agent controls are truthful: the user sees and controls exactly what each agent does.

**Why not the others**: Fix A (labeled button) still implies a global action over a per-agent model. Fix B (toggle with label) adds clarity but preserves the wrong interaction model. Both create second-order confusion: "I paused globally, but what happened to each agent's state?"

**Apple doc basis**: macOS HIG prefers text labels over ambiguous controls. "Pause Access" as text is unambiguous. A toggle is not.

---

### 1.6 — Tab bar visually disconnected

**Decision: Fix C — Keep tabs clean, improve content areas**

Leave the tab bar minimal. The segmented control in the toolbar is structurally correct and will auto-adopt Liquid Glass. Adding badges or dots would add visual noise to the navigation layer — violating the WWDC25 principle that glass is a calm navigation plane.

**Why this fix**: The tabs aren't the problem. The content areas behind them are. Fixes 1.1 through 1.5 transform the Overview into a rich dashboard. Fixes 2.1–2.7 transform Files into a native data table. Fixes 3.1–3.6 and 4.1–4.7 transform Emails. With strong content, the tabs become what they should be: simple wayfinding.

**Why not the others**: Fix A (badge counts) puts numeric data into the navigation layer, which competes with the monochromatic toolbar. Fix B (status dots) creates an iOS notification pattern that's foreign to macOS tab controls.

**Apple doc basis**: WWDC25 Session 356: "remove background colors from custom toolbars and tab bars. Rely on layout and grouping to express hierarchy rather than unnecessary decoration."

---

### 1.7 — "Agent" label text wrapping / clipping

**Decision: Fix A — Remove the "Agent" label entirely**

The Claude | Codex | Compare segmented control is self-explanatory. The "Agent" label adds zero information and introduces a layout bug. Delete it. Add `.accessibilityLabel("Agent focus")` to the segmented control for VoiceOver.

**Why this fix**: If removing a UI element improves the interface, it wasn't earning its space. The segmented control's content IS the label. Apple's segmented control HIG shows no external labels for controls whose segments are self-describing.

**Why not the others**: Fix B (compact label) is a workaround for a label that shouldn't exist. Fix C (layout constraint fix) patches the symptom but leaves the cause: a redundant element taking space.

---

## SCREENSHOT 2: FILES TAB

---

### 2.1 — Empty table rows (gray placeholder stripes)

**Decision: Fix A — Remove all placeholder rows**

End the table at the last real row. Below: a clean summary footer: "5 sources · 247 files · Add Folder…" (the "Add Folder…" is a text link, not a button). This is standard macOS table behavior — Finder, Xcode, and Mail stop at the last item.

**Why this fix**: No macOS app in Apple's ecosystem shows fake placeholder rows below real data. This is a bug, not a design decision. The summary footer converts dead space into useful information + action, following the ContentUnavailableView pattern adapted for a partially-populated state.

**Why not the others**: Fix B (subtle empty state) is close but makes the footer too prominent — a single-line summary is sufficient. Fix C (single empty row) is a half-measure.

---

### 2.2 — Items column shows "—" for every row

**Decision: Fix B — Lazy count with placeholder**

Show "…" as a placeholder, trigger background enumeration on appearance, replace with real count when available. Use `.contentTransition(.numericText())` per DESIGN-STANDARDS §5.1 for the animated transition. If enumeration fails or is unsupported for a source, show "—" with a tooltip explaining why.

**Why this fix**: This is the Finder pattern. When you select a folder and press ⌘I, Finder shows "Calculating size…" then the real number. The key insight: the column exists because file counts are valuable. Removing the column (Fix C) throws away useful information. Showing dashes forever (status quo) is worse than no column. The middle path — async populate with animation — is what Apple does.

**Why not the others**: Fix A (loading state per row) is too noisy with spinners. Fix C (remove column) discards useful data. Fix B preserves the information while being honest about its availability.

---

### 2.3 — Access checkboxes lack context

**Decision: Fix A — Agent-colored checkboxes**

When focused on Claude, checkboxes render in ClaudeBlue. When Codex, in CodexPurple. In Compare mode, the single access column splits into two columns: "Claude" (blue header) and "Codex" (purple header). The column header text always names the agent, satisfying the color-only prohibition.

**Why this fix**: The access column is Manifold's reason for existing. It should be the most visually clear element in the table. Agent-colored checkboxes create instant visual identity — you never wonder "whose access am I seeing?" The Compare mode with dual columns is how you'd naturally answer "do both agents have access to this folder?"

**Why not the others**: Fix B (text labels "Granted"/"No Access") is verbose for a table that could have many rows — checkboxes are more scannable. Fix C (agent icon in header) is additive, not sufficient — the header text already changes per this fix.

**Apple doc basis**: HIG Lists and Tables: use standard controls (checkboxes) in table columns. The color tint is agent identity, always paired with text.

---

### 2.4 — Sidebar lacks visual hierarchy

**Decision: Fix A — Section headers with prominence**

Use `.headerProminence(.increased)` for "Sources" and "Versions" section headers. Add item counts in `Type.numericCaption` with `.foregroundStyle(.secondary)`: "Sources (5)", "Versions (12)". Use 12pt spacing between sections. The "Add Folder…" and "View Activity" actions go into a separate "Actions" section at the bottom or become context-menu only.

**Why this fix**: This is how Finder, Mail, Notes, and Reminders structure their sidebars. `.headerProminence(.increased)` is the standard macOS API for creating visual hierarchy in sidebar section headers. It auto-adopts Liquid Glass styling and future design updates.

**Why not the others**: Fix B (agent-colored dots) is additive information that belongs on the table rows, not the sidebar. Fix C (second-line metadata) adds too much density to the sidebar — paths belong in the table, not the navigation.

---

### 2.5 — "Agent" label wrapping (same as 1.7)

**Decision: Fix A — Remove the label.** (Same rationale as 1.7.)

---

### 2.6 — "Activity" header doesn't match Files content

**Decision: Fix A — Dynamic title per tab**

The content header title changes to reflect the current view: Overview → "Overview", Files → "Sources" (or the selected source name when drilled in), Emails → "Domains" or "Messages" depending on sidebar selection. The title always describes what you're looking at.

**Why this fix**: This is basic information architecture. Mail shows the mailbox name. Finder shows the folder name. Notes shows the note title. The header IS the breadcrumb. Showing "Activity" on the Files tab is an information architecture bug.

**Why not the others**: Fix B (remove title) loses a useful orientation cue. Fix C (breadcrumb) is more complex to implement and isn't necessary in a shallow hierarchy.

---

### 2.7 — Table lacks visual rhythm and density

**Decision: Fix B — Use native SwiftUI `Table` component**

If not already using SwiftUI `Table`, switch to it. Native `Table` gives: click-to-sort column headers, proper column resizing, row hover highlighting, selection management, keyboard navigation, and accessibility — all for free. Use hard scroll edge effect (per WWDC25 Session 356) for pinned column headers on macOS. Reduce row padding to the system default. Right-align the Items (numeric) column.

**Why this fix**: This is the single highest-ROI change in the entire audit. SwiftUI `Table` is Apple's purpose-built component for exactly this use case: sortable, selectable, multi-column data on macOS. It auto-adopts the new design system, scroll edge effects, Liquid Glass toolbar integration, and accessibility. Fighting it with custom List+HStack layouts means reimplementing everything `Table` gives for free.

**Why not the others**: Fix A (tighten row height + add dividers) is manual work that `Table` handles automatically. Fix C (density toggle) is scope creep — pick one density and commit. DESIGN-STANDARDS calls for "comfortable utility" — system-default Table row height IS that density.

**Apple doc basis**: HIG Lists and Tables, WWDC25 Session 310: "a lot of unseen complexity to the system implementation" of split views and tables. Use the framework.

---

## SCREENSHOT 3: EMAILS — DOMAINS VIEW

---

### 3.1 — Domain list is an undifferentiated wall

**Decision: Fix A — Visual weight by volume**

Scale visual treatment by email count. Domains with 100+ emails: `Type.body` weight. Domains with 10–99: `Type.body` with `.foregroundStyle(.secondary)`. Domains with <10: `Type.caption`. The email count is a right-aligned `Type.numericCaption` badge. This creates an information-density heat map through typography alone — the most important domains visually dominate without any icons, colors, or cards.

**Why this fix**: Typography IS hierarchy. This is how Things 3 differentiates project importance, how Bear handles note prominence, and how Finder handles file sizes in list view (large files are immediately scannable). No category icons, no cards, no feature creep — just the type system doing its job.

**Why not the others**: Fix B (category grouping with icons) is feature creep — categorizing domains requires domain classification logic, which is a product feature, not a polish item. Fix C (domain cards) adds visual weight to a view that needs to handle 20+ domains in a scannable list.

**Apple doc basis**: WWDC25 Design Lab: "Express hierarchy through layout" — typography weight is layout hierarchy.

---

### 3.2 — Access toggle column is invisible

**Decision: Fix C — Inline toggle with color change**

Keep the toggle (it's a standard macOS control) but make it dramatically visible: ON = filled in the focused agent's color (ClaudeBlue or CodexPurple), OFF = clear gray with a visible 1pt border. Toggle width minimum 24pt. State change animates with `Anim.stateChange`. The toggle is always paired with column header text naming the agent.

**Why this fix**: Toggles are the standard macOS control for on/off state. The problem isn't the control type — it's the visibility. Increasing contrast and adding agent color makes the toggle serve double duty: access state AND agent identity. This follows the same pattern as 2.3 (agent-colored checkboxes) for visual consistency.

**Why not the others**: Fix A (colored dots with symbols) replaces a standard control with a custom one. Fix B (text labels) is verbose for a compact domain list that could have 20+ rows.

**Consistency check**: Agent-colored access controls are now the pattern across both Files (checkboxes, fix 2.3) and Emails (toggles, fix 3.2). The control type differs (checkbox for static table, toggle for governable list) but the color language is identical.

---

### 3.3 — Sensitivity picker truncated

**Decision: Fix B — Segmented control**

Replace the dropdown picker with a segmented control: `Permissive | Moderate | Strict`. Always visible, never truncates, current state always clear. Three fixed options is the ideal use case for a segmented control per Apple HIG.

**Why this fix**: Apple HIG explicitly recommends segmented controls for 2–5 mutually exclusive fixed options. A dropdown picker that truncates is a worse version of what a segmented control does natively. The current state is always visible, which matters for a security control — you should always know your sensitivity level at a glance.

**Why not the others**: Fix A (wider picker) is a band-aid. Fix C (move to sidebar/section header) moves a toolbar-level control out of the toolbar, which breaks the established control-placement pattern.

**Apple doc basis**: HIG Segmented Controls: "Use a segmented control to offer choices that are closely related but mutually exclusive."

---

### 3.4 — "1 emails" grammar error

**Decision: Fix A — Proper pluralization**

Use SwiftUI's automatic grammar agreement: `Text("^[\(count) email](inflect: true)")`. This handles English pluralization automatically and is the foundation for future localization. One line of code, zero ongoing maintenance.

**Why this fix**: This is the Apple-recommended approach. It's not a design decision — it's a bug fix using the correct API.

---

### 3.5 — Sidebar is sparse

**Decision: Fix B — Add domain categories to sidebar**

Show domain categories as sidebar items below "All Domains": Work, Automated, Personal (plus any user-defined categories). Selecting a category filters the domain table. Add counts in `Type.numericCaption` with `.foregroundStyle(.secondary)`: "Work (12)", "Automated (5)". Use `.headerProminence(.increased)` for the "Categories" section header, matching the Files sidebar pattern from fix 2.4.

**Why this fix**: A sidebar with 4 items is a sidebar that hasn't earned its space. Domain categories give the sidebar a job: filtering a potentially large domain list into manageable sections. This is the Mail.app smart mailbox approach — computed views based on domain characteristics.

**Why not the others**: Fix A (full folder tree in both views) creates two complex sidebars when the Domains view doesn't need folder-level navigation. Fix C (remove sidebar) loses the structural consistency with the rest of the app where every tab has a sidebar.

**Scope note**: The categorization logic (Work vs Automated vs Personal) should be simple — based on domain heuristics, not ML classification. Keep it honest: if the app isn't confident, don't categorize.

---

### 3.6 — No visual connection between agent control and data

**Decision: Fix C — Row tinting for granted domains**

Domains that the focused agent can access get a subtle row tint in the agent's color at `Opacity.rowTint` (0.04). Domains without access have no tint. Switching agents with the segmented control animates the tint change with `Anim.stateChange`. In Compare mode, rows where both agents have access get a neutral tint; rows where only one agent has access get that agent's color.

**Why this fix**: This creates an instant visual map: colored rows = this agent can see these domains. No tint = no access. The information is ambient — the user sees the access landscape without reading every toggle. At 0.04 opacity, the tint is calm (not a colored stripe) but visible.

**Why not the others**: Fix A (tinted header bar) puts agent color in the toolbar, which violates the monochromatic toolbar principle from WWDC25. Fix B (agent name in column header) is already happening via fix 3.2's column header — but it's not sufficient alone because the user has to read the header then check each toggle. Row tinting makes the pattern scannable.

**Consistency check**: Row tinting at `Opacity.rowTint` is now the pattern for agent-access visualization across both Files (via Table row backgrounds) and Emails (domain rows). Same opacity, same colors, same animation. One design language.

---

## SCREENSHOT 4: EMAILS — MESSAGES VIEW

---

### 4.1 — Sidebar too narrow, everything truncates

**Decision: Fix A — Increase minimum sidebar width**

Set `.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)` on the sidebar column. "Sent Messages", "Deleted Items", "Smart Mailboxes" must all fit without truncation at the minimum width. User can drag wider.

**Why this fix**: NavigationSplitView on macOS supports `min:ideal:max` column widths. The sidebar is too narrow because the minimum is set too low (or not set at all). This is a one-line fix that solves issues 4.1 and 4.6 simultaneously. 220pt is the standard Mail.app sidebar minimum.

**Why not the others**: Fix B (abbreviated labels) trades clarity for compactness — "Sent" vs "Sent Messages" loses information. Fix C (two-tier sidebar) is an architectural change that isn't necessary when the real problem is a width constraint.

**Apple doc basis**: NavigationSplitView API: `.navigationSplitViewColumnWidth(min:ideal:max:)` — this is the purpose-built API for exactly this problem.

---

### 4.2 — Empty message list hedges ("empty or still syncing")

**Decision: Fix A — Distinguish syncing from empty**

If syncing: show `ProgressView("Syncing messages…")` with the account name. If truly empty: show `ContentUnavailableView` with "No unviewed messages" and description "All caught up. Select another mailbox to browse." with an action button linking to the mailbox with the most messages. Never use "or."

**Why this fix**: Decision principle 7 (honest state). "Empty or still syncing" is an admission that the app doesn't know its own state. A trust app that can't tell you whether it's loading or empty has no credibility to tell you what your AI agents are doing. ContentUnavailableView with differentiated states is the Apple-standard pattern.

**Why not the others**: Fix B (sync status line) is additive — adding "Last synced: 2 min ago" is good but doesn't solve the core problem of the hedging empty state. We should do both: fix the empty state AND add sync timestamps, but the primary fix is A. Fix C (proactive navigation) is good UX and is included in Fix A's action button.

**Apple doc basis**: ContentUnavailableView docs: three view builders (label, description, actions). Use the actions parameter to provide a recovery path.

---

### 4.3 — Reading pane empty state is cold

**Decision: Fix A — Warm copy with keyboard hint**

Replace the generic empty state with: Title "Select a message", Description "Use ↑↓ to navigate the message list, Space to scroll." Icon: the relevant tab SF Symbol (envelope) at 32pt in `.foregroundStyle(.secondary)`. Background: `.quaternarySystemFill` to subtly distinguish the reading pane from the message list.

**Why this fix**: The reading pane is the largest area on screen when no message is selected. Making it helpful (teaching keyboard shortcuts) turns dead space into onboarding. This follows Apple's ContentUnavailableView pattern: tell the user what goes here, why it's empty, and what to do next. The keyboard hint is particularly macOS-native — Mac users expect keyboard navigation.

**Why not the others**: Fix B (account summary) puts the wrong content in the wrong place — account info belongs in the sidebar or settings. Fix C (minimal refinement) improves aesthetics but misses the opportunity to teach.

---

### 4.4 — Double search icons

**Decision: Fix A — Remove one**

One search icon in the toolbar, always. Determine which search scope is correct for the current context (mailbox search if a mailbox is selected, global email search otherwise) and remove the redundant icon. Use `.searchable(text:)` on the NavigationSplitView per WWDC25 guidance, which handles scope automatically.

**Why this fix**: WWDC25 Design Lab: "Do you need six buttons? Could you use a menu?" Two identical icons is a bug. The `.searchable` modifier on NavigationSplitView automatically places search correctly and handles scope. Using the standard modifier eliminates the need for any manual search icon placement.

**Why not the others**: Fix B (differentiate visually) preserves a confusing dual-search model. Fix C (change one to filter) assumes a filter function exists — if it does, the filter should be a toolbar item with the standard `line.3.horizontal.decrease` icon, but that's a separate item, not a search replacement.

**Apple doc basis**: WWDC25 UI Frameworks Lab: ".searchable modifier with TabView for optimal integration — gives you that great morph animation."

---

### 4.5 — Folder tree has no visual hierarchy

**Decision: Fix C — Collapsible sections with disclosure triangles**

Make each section (Favorites, Smart Mailboxes, Account folders) a proper `DisclosureGroup` with `.headerProminence(.increased)`. The user can collapse sections they don't need. Default state: Favorites expanded, Smart Mailboxes expanded, Account expanded. This is the Mail.app sidebar pattern.

**Why this fix**: `DisclosureGroup` is the standard SwiftUI API for collapsible sections. It gives the user control over sidebar density, auto-adopts Liquid Glass sidebar styling, and creates the visual hierarchy through indentation and disclosure arrows that macOS users expect. This also works naturally with the increased sidebar width from fix 4.1.

**Why not the others**: Fix A (section headers without collapse) doesn't let users manage complexity. Fix B (indentation without headers) is too subtle for three structurally different section types (pinned shortcuts, computed filters, IMAP folders).

**Consistency check**: Both Files sidebar (fix 2.4) and Emails sidebar (fix 4.5) now use `.headerProminence(.increased)` for section headers. Files uses static sections (Sources, Versions). Emails uses collapsible `DisclosureGroup`. The header style is consistent; the interaction differs based on content complexity.

---

### 4.6 — "Add Acco..." button truncated

**Decision: Fix B — Icon-only "+" button**

Replace "Add Account…" with a `+` icon button at the bottom of the sidebar, like Mail.app's sidebar footer. Tooltip on hover: "Add Email Account…" using `.help("Add Email Account…")`. This works at any sidebar width and follows the Mail.app precedent exactly.

**Why this fix**: Fix A (wider sidebar) is already happening via 4.1, but the "Add Account" button should be robust at any width. A `+` icon is universally understood for "add" in macOS sidebars (Mail, Reminders, Notes all use it). The tooltip provides the full text for clarity. This action is used once during setup, not daily — it doesn't need prominent text.

**Why not the others**: Fix A alone would fix the truncation but leaves a full-text button for a rare action. Fix C (move to Settings) hides discoverability — a new user looking at an empty email sidebar needs to see how to add an account.

**Apple doc basis**: macOS HIG: "prefer text labels" applies to frequent actions. For infrequent setup actions at the bottom of a sidebar, icon + tooltip is the established macOS pattern (Mail.app, Notes.app, Reminders.app).

---

### 4.7 — Three-pane layout proportions wrong

**Decision: Fix B — NavigationSplitView with proper column constraints**

Use `NavigationSplitView` with `.balanced` style and explicit column widths:
- Sidebar: `min: 220, ideal: 240, max: 320`
- Message list: `min: 260, ideal: 300, max: 450`
- Reading pane: takes remaining space (no explicit constraint — it's the flexible column)

Let the user drag dividers. Let the framework manage proportions. This matches Apple's recommended approach for three-column email/message layouts.

**Why this fix**: `NavigationSplitView` with `.balanced` is exactly how Apple intends three-column layouts to work on macOS. Setting explicit `min:ideal:max` values prevents the narrow-sidebar problem (fix 4.1) and the over-wide-reading-pane problem simultaneously. The framework handles fullscreen, split-screen, and window resize automatically.

**Why not the others**: Fix A (two-pane until selection) changes the expected email client layout. Users who've used Mail.app expect three persistent panes. Fix C (responsive collapse) is already handled by NavigationSplitView's built-in responsive behavior — it auto-collapses columns at narrow widths.

**Apple doc basis**: NavigationSplitView API: balanced style "reduces the size of the detail view as the sidebar or content bar is shown." WWDC25 UI Frameworks Lab: "there's a lot of unseen complexity to the system implementation — scroll edge effects, layering, and fullscreen behaviors." Use the framework.

---

## CROSS-CUTTING ISSUES

---

### X.1 — No app icon

**Decision: All fixes apply — covered by backlog item A-02.**

Use Icon Composer (WWDC25 Design Lab: "one icon built in Icon Composer works across iOS and macOS — no platform-specific versions needed"). The icon gets Liquid Glass specular treatment automatically. Communicate: protection, visibility, trust.

---

### X.2 — No brand identity anywhere

**Decision: Fix A — Agent colors as ambient identity**

ClaudeBlue and CodexPurple become Manifold's visual identity. They appear in: card left borders (1.2), status dots (1.2), access checkboxes (2.3), access toggles (3.2), row tinting (3.6), sidebar dots, and title bar status text (1.3). The agent colors are always present as an ambient layer — not dominant, not decorative, but woven into the information.

**Why this fix**: Manifold's identity IS the agent relationship. The app exists to mediate between you and your AI agents. Making the agents visually present everywhere — through color, not logos or illustrations — communicates that identity without any brand exercise.

**Why not the others**: Fix B (distinctive sidebar tint) would fight Liquid Glass — the sidebar is now inset glass, and adding a custom background color contradicts WWDC25 guidance ("remove background colors"). Fix C (SF Pro Rounded for headings) adds typographic personality but doesn't communicate what Manifold is about.

**Apple doc basis**: WWDC25 Design Lab: background color behind toolbars "comes through and interacts delightfully with liquid glass, allowing effective branding without customization." The agent colors in content (not chrome) achieve branding through content.

---

### X.3 — Inconsistent density across tabs

**Decision: Fix A — Establish target density: "comfortable utility"**

The target density is "comfortable utility" — Things 3, Fantastical, the middle ground between Xcode (dense professional) and Notes (spacious consumer). Concretely: system-default SwiftUI `Table` row heights, `Type.body` (.callout) as primary text, 8pt standard spacing, 12pt section spacing. Apply this uniformly. Every view should feel like the same app.

**Why this fix**: "Show me the incentive and I'll tell you the outcome." If each view has different density, the incentive for each developer who touches a view is to optimize locally. The outcome is an app that feels assembled from parts. A global density target prevents this.

**Why not the others**: Fix B (content-aware density) creates the inconsistency it aims to solve. Fix C (minimum content guarantee) is a good heuristic but doesn't define the actual spacing/typography rules — it's a goal, not a method.

---

### X.4 — No connection/status state visible anywhere

**Decision: Fix A — Persistent status indicator in toolbar**

A small filled circle (10pt) in the toolbar: `StatusActive` green when both agents connected, `StatusWarning` orange when partially connected, `StatusDanger` red when disconnected. On hover or click, expands to show per-agent status: "Claude: Connected · Codex: Paused". Always visible on every tab.

Paired with a text label (satisfying color-only prohibition): the circle sits next to small text reading "Connected" or "1 agent paused" or "Disconnected" in `Type.caption`.

**Why this fix**: This is the Xcode build-status pattern: always visible, never distracting, expands for detail on demand. For a trust app, the single most important ambient signal is "is this thing working?" The user should never have to navigate to a specific tab or setting to answer that question.

**Why not the others**: Fix B (connection state in agent cards) only appears on the Overview tab — invisible on Files and Emails. Fix C (status bar footer) steals vertical space from content on every view. A toolbar indicator is the lightest-weight option with the broadest visibility.

**Apple doc basis**: WWDC25 Design Lab: color for "status indicators consistent across the app." A connection status dot is the canonical example.

---

## Decision summary table

| Issue | Selected Fix | Key Apple Reference |
|-------|-------------|-------------------|
| 1.1 Dead space | A — Cards become dashboards | Content dominates the window |
| 1.2 Cards no weight | A — Agent color identity (left border + shadow + tint) | Fantastical calendar-color pattern |
| 1.3 Legacy "sessions" | B — Truthful status subtitle | Honest state principle |
| 1.4 Orphaned CTA | A — Integrate into card footer | Actions near context |
| 1.5 Ambiguous toggle | C — Move controls to agent cards | Per-agent model; text labels on macOS |
| 1.6 Tab bar disconnected | C — Keep clean, improve content | Remove toolbar decoration (WWDC25 356) |
| 1.7 "Agent" label wrapping | A — Remove the label | Self-describing controls need no label |
| 2.1 Empty table rows | A — Remove placeholder rows | Standard macOS Table behavior |
| 2.2 Items column dashes | B — Lazy count with placeholder | Finder "Calculating…" pattern |
| 2.3 Access checkboxes | A — Agent-colored checkboxes | Color for consistent status indicators |
| 2.4 Sidebar flat | A — Section headers with prominence | .headerProminence(.increased) |
| 2.5 Agent label (same) | A — Remove the label | (Same as 1.7) |
| 2.6 Title mismatch | A — Dynamic title per tab | Header describes content |
| 2.7 Table lacks rhythm | B — Native SwiftUI Table | HIG Lists and Tables; hard scroll edge |
| 3.1 Domain wall | A — Typography weight by volume | Hierarchy through layout |
| 3.2 Access toggle invisible | C — Toggle with agent color | Standard control + status color |
| 3.3 Sensitivity truncated | B — Segmented control | HIG Segmented Controls |
| 3.4 Grammar error | A — SwiftUI inflect: true | Automatic grammar agreement |
| 3.5 Sidebar sparse | B — Domain categories | Mail.app smart mailbox pattern |
| 3.6 No agent-data connection | C — Row tinting at 0.04 opacity | Ambient information through tint |
| 4.1 Sidebar too narrow | A — min: 220, ideal: 240, max: 320 | NavigationSplitView column width API |
| 4.2 Empty state hedges | A — Distinguish syncing from empty | ContentUnavailableView + honest state |
| 4.3 Reading pane cold | A — Warm copy with keyboard hints | ContentUnavailableView with description |
| 4.4 Double search icons | A — Remove one; use .searchable | WWDC25 UI Lab: searchable modifier |
| 4.5 Folder tree flat | C — Collapsible DisclosureGroups | Mail.app sidebar pattern |
| 4.6 Truncated button | B — Icon-only "+" with tooltip | Mail/Notes/Reminders sidebar pattern |
| 4.7 Layout proportions | B — NavigationSplitView.balanced | NavigationSplitView min:ideal:max API |
| X.1 No app icon | A-02 in backlog | Icon Composer (WWDC25 Design Lab) |
| X.2 No brand identity | A — Agent colors as ambient identity | Branding through content, not chrome |
| X.3 Inconsistent density | A — "Comfortable utility" target | Uniform density across all views |
| X.4 No status indicator | A — Toolbar status dot + text | Xcode build-status pattern |

---

## Coherence verification

These decisions were checked against each other for conflicts:

1. **Agent color language is consistent**: ClaudeBlue and CodexPurple appear in card borders (1.2), checkboxes (2.3), toggles (3.2), row tints (3.6), status text (1.3), and the toolbar status dot (X.4). Always at defined opacity levels. Always paired with text labels.

2. **Sidebar pattern is consistent**: Both Files (2.4) and Emails (4.5) use `.headerProminence(.increased)` section headers with counts. Emails adds `DisclosureGroup` for its deeper hierarchy. Same visual language, appropriate interaction complexity.

3. **Toolbar is monochromatic**: No fix adds color to the toolbar except the status indicator (X.4), which is explicitly permitted by WWDC25 guidance as a "status indicator consistent across the app."

4. **Empty states are differentiated**: Overview (1.1) fills space with data. Files (2.1) uses summary footer. Emails/Messages (4.2) distinguishes syncing from empty. Reading pane (4.3) teaches keyboard shortcuts. Each empty state is specific to its context.

5. **Native components throughout**: SwiftUI `Table` (2.7), `NavigationSplitView` (4.7), `ContentUnavailableView` (4.2, 4.3), `DisclosureGroup` (4.5), `.headerProminence` (2.4, 4.5), `.searchable` (4.4), `Text("inflect: true")` (3.4). Maximum framework leverage.

6. **No fix fights Liquid Glass**: No custom toolbar backgrounds. No nested glass. No glass inside scroll views. Hard scroll edge for pinned table headers (2.7). Sidebar inset with glass (4.1, 4.7). All per WWDC25 Session 356.

7. **Density target is uniform**: "Comfortable utility" across all views. System-default Table row heights. `Type.body` (.callout) as primary text. 8pt standard spacing. No view-specific density overrides.
