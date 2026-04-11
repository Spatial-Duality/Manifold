# Manifold — Polish Audit v2

> **What this is**: An inventory of every gap between Manifold's current state and Apple Design Award quality. Findings only — no prescriptions, no estimates. Solutions live in DESIGN-STANDARDS.md. Execution lives in POLISH-BACKLOG.md.
>
> **Benchmark**: Pixelmator Pro, Things 3, Bear, Craft, Fantastical.
>
> **Scope**: 78+ SwiftUI views, 10 components, 7+ sheets, 4 settings panes, 1 onboarding wizard, 1 menu bar extra.
>
> **Assumes**: v5.2 redesign and menu bar spec are implemented. This covers everything else.

---

## Principles

1. **Native** — Manifold should feel like it was built by the same team that built Mail, Finder, and System Settings. Platform conventions over custom solutions.
2. **Trustworthy** — This app controls what AI can see. Every UI surface must make the user feel safe, informed, and in control. Trust is the product.
3. **Calm** — A security/access tool should be quiet. No gratuitous animation, no loud colors, no attention-seeking. Confidence through restraint.
4. **Legible** — Every state should be readable at a glance. Status, access scope, what changed, and what to do next should never require hunting.
5. **Recoverable** — Every action should be undoable or confirmable. No silent destructive operations. The user should never fear clicking.

---

## Non-goals

These are out of scope for the polish pass. They may be valuable later, but including them now dilutes the objective.

- **Document type / UTI registration** — No user-facing document format exists yet. Premature.
- **PDF report generation** — Enterprise feature. Not needed for v1.
- **Haptic feedback** — macOS haptic support is limited (trackpad only) and optional. Not a polish priority.
- **Email message density toggle** (Compact / Default / Relaxed) — New feature, not polish.
- **Smart mailbox template system** — New feature, not polish.
- **Smart mailbox preview** ("X messages match") — New feature, not polish.
- **Toolbar customization** (.toolbarRole(.editor)) — Adds QA burden with little value for a focused utility.
- **Email reply / forward / trash actions** — New email client features, not polish.
- **Multiple window support** — Manifold is a singleton control surface. Prevent ⌘N from creating duplicates, but don't build multi-window.

---

## 1. APP IDENTITY

### 1.1 No app icon

Manifold has no custom app icon. The Dock shows a generic SwiftUI icon. `shield.checkered` (an SF Symbol) is used as a stand-in everywhere. This is the single most visible signal that the app is a prototype.

**Why it matters**: The app icon is the first thing a user sees in the Dock, Spotlight, Finder, and the App Store. It forms more first impressions than any other surface.

### 1.2 No asset catalog

No `.xcassets` directory exists. No color sets, no image sets, no data assets. This means agent colors (`.blue`, `.purple`) are hardcoded as SwiftUI color literals across 40+ files, status colors are inconsistent, and there's no single source of truth for the app's visual identity.

**Why it matters**: Without named colors in an asset catalog, dark mode, high contrast, and color consistency are all manual and fragile. Every color change requires a multi-file grep.

### 1.3 Menu bar icon is generic

Uses `shield.checkered` / `shield.checkered.fill`. Too generic to be recognizable among 15+ menu bar items.

**Why it matters**: The menu bar icon is how users confirm Manifold is running. It needs to be instantly recognizable at 18×18pt.

### 1.4 No About window

macOS shows a generic "About Manifold" with no icon, no credits, no version beyond Info.plist.

**Why it matters**: The About window is a small surface that communicates care. Every polished Mac app has one.

---

## 2. DESIGN SYSTEM GAPS

### 2.1 No typography scale

Every view picks its own `.font()` ad hoc. No shared type scale exists. This creates visual inconsistency — some views use `.headline` where others use `.title3`, some use `.callout` where others use `.body`.

**Why it matters**: Typography is the primary visual system in a text-heavy app. Inconsistency makes the app feel assembled from parts.

### 2.2 No shadow, opacity, or animation presets

`Spacing.swift` defines spacing and corner radii but nothing else. Shadows, opacity values, and animation curves are invented inline at each call site.

**Why it matters**: Without shared presets, every developer (or coding agent) makes different choices. The app accumulates visual drift.

### 2.3 No unified badge/pill component

StatusBadge, the state chips in AgentPolicyCard, and the connection badges all use slightly different capsule/pill patterns — different padding, different font weights, different opacity values.

**Why it matters**: Badges are a core visual language in Manifold (active/paused, connected/disconnected, agent identity). Inconsistency undermines the status-at-a-glance goal.

### 2.4 Agent colors hardcoded

`.blue` and `.purple` literals scattered across 40+ files. No semantic color names. Status colors (green for active, orange for paused, red for danger) are also hardcoded.

**Why it matters**: Can't verify dark mode, high contrast, or color-blindness compliance without named colors. A color change requires touching dozens of files.

---

## 3. EMPTY, LOADING, AND ERROR STATES

### 3.1 Empty states are placeholder-grade

Most use a generic `ContentUnavailableView` with an SF Symbol. None answer the three questions: what would be here, why is it empty, what do I do next. The Email Smart Mailbox section uses a full-size `ContentUnavailableView` for a section-level empty — disproportionate.

**Why it matters**: Empty states are the first thing new users see. They set emotional tone. Placeholder empties say "this app isn't finished."

### 3.2 Loading states are sparse

Most loading states are a generic `ProgressView()`. Some views (source enumeration, content search, email sync) have no loading indication at all. Initial app launch shows a flash of empty content before data appears.

**Why it matters**: Missing loading states make the app feel broken during legitimate waits. Users see "empty" and think "nothing here" rather than "loading."

### 3.3 Error handling is catch-all

`MainView` shows `store.lastError` as a string in a banner. No categorization (connection vs. permission vs. database vs. network). No auto-dismiss for non-critical errors. No recovery actions beyond "dismiss." Raw Swift error strings sometimes surface as user-facing text.

**Why it matters**: For a trust app, "something went wrong" with no explanation and no recovery path is the opposite of the product promise.

---

## 4. TRUST, PRIVACY, AND PERMISSION UX

This section does not exist in the current app. For Manifold specifically, trust is not branding — it is the product. Every surface where the user interacts with access control, data visibility, or audit history must communicate safety.

### 4.1 No "why am I seeing this?" explanations

When a file shows as "accessible by Claude," there's no way to understand why — which policy granted it, when, whether it was part of a work block or standing access.

**Why it matters**: Users need to understand the access state to trust it. Unexplained states breed anxiety.

### 4.2 No data locality assurance

The app doesn't communicate what stays local and what leaves the device. There's no privacy summary, no data flow explanation, no "your data never leaves your Mac" messaging.

**Why it matters**: Users are entrusting Manifold with access control over their files and email. They need reassurance that Manifold itself isn't a data leak.

### 4.3 Destructive action explanations are thin

Removing a source is immediate (narrowing per v4.1), but version history implications aren't explained. "Remove from Manifold" doesn't say what happens to tracked versions.

**Why it matters**: In a security tool, every destructive action should explain consequences before execution.

### 4.4 Audit/history presentation is utilitarian

ActivityView shows events in a list. There's no summary view, no "what changed this week" overview, no easy way to verify "Claude only accessed what I said it could."

**Why it matters**: The audit trail is how users verify trust. If it's hard to read, users won't check it, and the trust promise becomes theoretical.

### 4.5 Remote image loading in email

`HTMLEmailView` resolves CID references but the remote image loading policy is unclear. If external images load by default, that leaks IP/timing information to senders.

**Why it matters**: For a privacy-focused app, default-loading remote email images is a contradiction.

### 4.6 Storage retention and cleanup copy

"Clean Up Storage" doesn't explain what it deletes. "Verify Database" shows a result but doesn't explain what was checked.

**Why it matters**: Users need to understand what data Manifold retains and what "cleanup" means before clicking.

---

## 5. NATIVE macOS CONVENTIONS

### 5.1 Menu bar audit (App / File / Edit / View / Window / Help)

The standard macOS menu bar has not been audited. Unknown gaps in:

- **File menu**: Should contain "Add Folder…" (⌘O or ⌘⇧O), "Add Email Account…"
- **Edit menu**: Standard text editing commands must work in all text fields (search, email fields, IMAP config). Undo/Redo should reflect app-level undo where applicable
- **View menu**: Should contain "Toggle Sidebar" (⌘⌃S or ⇧⌘S), tab switching shortcuts, "Show Inspector" if inspectors exist
- **Window menu**: "Minimize" (⌘M), "Zoom", "Bring All to Front", access to main window from menu bar
- **Help menu**: Should contain "Manifold Help" (even if it opens a website), search field for menu items (macOS provides this automatically)

**Why it matters**: Incomplete menus make the app feel like it wasn't built for macOS. Power users and VoiceOver users navigate via menus.

### 5.2 Keyboard shortcuts not discoverable in menus

Access menu commands exist (Review Access ⌘⇧R, Track Changes ⌘⇧W, Pause Access ⌘⇧P) but it's unclear whether they appear in the menu bar. Shortcuts that don't appear in menus are invisible.

**Why it matters**: macOS users discover keyboard shortcuts by browsing menus. If the shortcut isn't in a menu, most users will never find it.

### 5.3 Window management gaps

- **Window restoration**: Unknown whether position, selected tab, sidebar selection, and inspector state persist on relaunch. Users expect `@SceneStorage` behavior
- **Full screen**: Untested. Sidebar, menu bar extra, and split-screen behavior unknown
- **Close/minimize/zoom**: Default behavior, but verify ⌘W behavior (should close window but keep app running, accessible from menu bar)
- **First responder**: Unknown whether keyboard focus moves correctly when switching tabs, opening sheets, dismissing popovers

**Why it matters**: These are invisible baseline expectations. Users don't notice when they work, but immediately feel something is wrong when they don't.

### 5.4 Context menus incomplete

| View | Has context menu | Missing |
|------|-----------------|---------|
| SourcesTableView row | Yes (Reveal, Remove) | Copy Path, View Activity |
| FilesView file row | Yes (Open, Reveal, Copy Path, Versions) | Share with Agent |
| DomainsTableView row | No | View Emails, Copy Domain, View Activity |
| EmailMessageRow | No | Flag, Share with Agent, Copy Subject |
| Sidebar source item | No | Reveal in Finder, Remove, View Activity |
| Sidebar email account | Yes | — (adequate) |

**Why it matters**: Right-click is a primary interaction pattern on macOS. Missing context menus make the app feel incomplete.

### 5.5 Drag and drop absent

No drag and drop support anywhere. Expected interactions: drag folders from Finder into sidebar (add source), drag file rows to Finder (reveal/export).

**Why it matters**: Drag and drop is a foundational macOS interaction. Its absence is conspicuous in a file-management-adjacent app.

### 5.6 Proxy icon / title bar

No proxy icon support. When a source is selected in Files, the window title doesn't reflect it. Users can't drag from the title bar.

**Why it matters**: Subtle but deeply native. Xcode, Finder, TextEdit, and every document-based app does this.

---

## 6. SURFACE-SPECIFIC FINDINGS

### 6.1 Overview tab

- Agent policy cards have no hover state signaling interactivity
- Cards don't maintain equal height when one agent has more summary lines
- "Start Tracked Work Block" CTA shows even when no sources are configured (meaningless)
- Transition from CTA → active work block banner may cause layout jump

### 6.2 Files tab

- Sidebar source dots always blue — should follow focused agent color
- Sidebar shows no item counts next to "Recently Modified" / "AI-Touched Files"
- Table numeric columns (Items, Size) may not be right-aligned
- Content search horizontal card scroll doesn't scale past ~5 results
- File type icons are generic (`doc`) — no type-specific differentiation
- "✨" emoji for AI-modified files should be an SF Symbol (`sparkles`)
- Sort selection doesn't persist per source
- Version detail: line numbers truncate at 1000+ lines, no word-level diff, no syntax highlighting, "No Versions" empty state doesn't explain when versions appear

### 6.3 Emails tab

- Domain favicons would elevate visual quality, but implementation must not leak domain data to third parties (see §4)
- Category icons use emoji (🏢 🤖 👤 🏦) — should be SF Symbols for consistency
- Domain section headers don't show counts
- Sensitivity change doesn't animate rows moving between sections
- Reading pane "Select an email" empty state is cold
- HTML email dark mode CSS injection needs verification
- Remote image loading policy unclear (see §4.5)
- Plain text emails not rendered in monospace
- Attachment thumbnails and Quick Look preview absent
- Search token design inconsistent with badges elsewhere
- `SelectionActionBar` says "Share with Cowork" — should say "Share with Claude/Codex"

### 6.4 Components

- `TimeLabel`: No live updates (2m → 3m), no tooltip with absolute time, uses custom formatter instead of shared `ManifoldDateFormatter`
- `AgentBadge`: Only one size variant. No compact (dot-only) or prominent variant
- `DiffView`: Fixed 24pt line number width, no word-level diff, no copy-diff button, no syntax highlighting
- `CommandPaletteView`: Unknown if fuzzy matching works, no recent commands, unknown if command icons exist
- `LiveCheckRow`: No "last checked" timestamp, no retry success/failure animation
- `TrackChangesToolbarContent`: No compact mode for narrow windows

### 6.5 Sheets and modals

- `ReviewAccessSheet`: Tab switch (Files ↔ Emails) may hard-cut instead of crossfade. Checkbox → "What's Changing" section lacks entrance animation. Footer sticky behavior unverified with long lists
- `ReviewChangesSheet`: Sections not collapsible for large changesets. No promote progress indicator. No success confirmation before dismiss
- `ShareWithCoworkSheet`: "Cowork" naming. No agent picker when both connected. No success feedback
- `EmailAccountSetupView` (838 lines, most complex modal): Progress dots too subtle, no manual provider override timeout, no password show/hide, connection steps lack time estimates, errors may be generic, OAuth buttons may lack brand styling, keyboard focus not set on appear, Tab order unverified

### 6.6 Settings

- **General** (22 lines): Only Launch at Login + Notifications. Missing: default agent focus, keyboard shortcuts reference, update checking, data & privacy section, menu bar toggle
- **AI Apps**: No "Test Connection" button, no "last connected" timestamp, MCP config path only in Connect sheet
- **Mail**: Accounts not reorderable, no inline sync status
- **Storage**: "Clean Up" unexplained (see §4.6), "Verify Database" result display minimal, version number in footer should be in About window

### 6.7 Onboarding

- Progress dots (8pt circles) too subtle — need step indicator with labels
- Welcome screen wastes prime real estate on "Welcome to Manifold" instead of explaining the product
- Connect Apps: skip button too prominent, MCP install gives no progress feedback, errors may fail silently
- Add Data: no feedback on added sources, no explanation that email is optional
- Review & Finish: doesn't show what was skipped, "Done" is neutral (should be "Get Started")
- Window close during onboarding: unclear whether it re-appears on next launch

---

## 7. CROSS-CUTTING CONCERNS

### 7.1 Accessibility

- Many interactive controls lack `.accessibilityLabel`
- Status indicators (colored dots, chips) communicate by color only in some views
- No systematic VoiceOver grouping (`.accessibilityElement(children: .contain)`) on cards
- Dynamic Type untested
- Reduce Motion coverage partial (v5.2 Phase 9.6 adds checks, but pre-existing animations unaudited)
- Keyboard focus not set on sheet appearance
- Tab order unverified in complex sheets (ReviewAccessSheet, EmailAccountSetupView)

### 7.2 Animation and motion

- Some views still use `.easeInOut` / `.easeIn` instead of named spring presets
- Entry/exit transitions inconsistent (some use `.move`, some use `.opacity`, some use nothing)
- Missing micro-animations: undo toast entrance, card state change, sidebar selection, table row tint change, badge count change, error banner entrance
- `contentTransition(.numericText())` used in some count displays but not all

### 7.3 Undo system

- Undo toasts exist in SourcesTableView and DomainsTableView but design is inconsistent
- No global undo stack — ⌘Z behavior scoped per-view
- Toast stacking behavior undefined (two rapid undos may overlap)
- Toast not announced to VoiceOver

### 7.4 Localization readiness

No `.xcstrings` or `.strings` files. All strings hardcoded in English. Retrofitting localization late is expensive.

**Note**: String extraction infrastructure should be earlier than it appears in the original audit. Translation can wait; the catalog cannot.

### 7.5 Performance edge cases

Untested at scale: 100+ sources, 10,000+ emails, 50+ smart mailboxes, 5000-line diffs, deeply nested file paths. Long paths need `.truncationMode(.middle)` everywhere.

---

## 8. WHAT'S NOT IN THIS AUDIT

This audit does not cover:

- **v5.2 redesign items** — Those are tracked separately in REDESIGN-PLAN-v5.2.md
- **Menu bar spec items** — Tracked in MENU-BAR-SPEC.md
- **New features** — This is about making existing surfaces feel finished, not adding scope
- **Backend / MCP bridge** — This is a UI audit only
- **App Store metadata** — Screenshots, description, keywords are a separate workstream
