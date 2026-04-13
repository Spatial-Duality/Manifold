# Manifold Polish Pass — Claude Code Prompt

You are implementing a comprehensive UI polish pass on Manifold, a native macOS SwiftUI app that controls what AI agents (Claude, Codex) can see on the user's Mac — files and email. The app is functional but prototype-grade. Your job is to bring it to Apple Design Award quality.

**Before you start any phase**, read these reference documents in the repo:
- `design/LAYOUT-SPEC-v4.md` — authoritative UI spec (Standing Access + Work Blocks model)
- `design/APPLE-DESIGN-EXCELLENCE-GUIDE.md` — platform constraints (Liquid Glass rules, spring presets, what not to build)
- `design/REDESIGN-PLAN-v5.2.md` — the structural redesign (assumed complete before this work begins)
- `design/MENU-BAR-SPEC.md` — menu bar implementation (assumed complete before this work begins)

---

## PRINCIPLES

1. **Native** — Feel like Mail, Finder, System Settings. Platform conventions over custom solutions.
2. **Trustworthy** — This app controls AI access. Every surface must make users feel safe, informed, in control.
3. **Calm** — Security tools should be quiet. No gratuitous animation, no loud colors. Confidence through restraint.
4. **Legible** — Every state readable at a glance. Status, access scope, what changed, what to do next.
5. **Recoverable** — Every action undoable or confirmable. No silent destructive operations.

## NON-GOALS — DO NOT BUILD THESE

- Document type / UTI registration
- PDF report generation
- Haptic feedback
- Email message density toggle (Compact/Default/Relaxed)
- Smart mailbox template or preview system
- Toolbar customization (.toolbarRole(.editor))
- Email reply / forward / trash actions
- Multiple window support (prevent ⌘N duplicates, but don't build multi-window)

## LABEL CONVENTIONS — USE THESE EXACT STRINGS

- "Pause Access" / "Resume Access" — button, NOT a toggle
- "Review & Update Access" — sheet name
- "Start Tracked Work Block" — never "session"
- "Claude" / "Codex" — agent names, never "Cowork" in user-facing text
- "Sources" — not "folders"
- "Domains" — not "senders"

## CONTENT VOICE

Manifold's voice is calm, factual, and respectful of the user's intelligence.
- Say what happened
- Say why the user is seeing it
- Say what to do next
- Prefer direct language over playful language
- Never blame the user
- Never use exclamation marks in error/warning copy
- Never expose raw Swift error strings, type names, or module paths as user-facing text
- Avoid "Oops", "Uh oh", "Something went wrong"

---

# DESIGN STANDARDS

Implement these shared primitives FIRST (Phase A). Reference them as the source of truth for all later phases. Every token, component, and rule below must exist as real code before surface-level polish begins.

## DS-1: COLOR SYSTEM

Create `Assets.xcassets` with these named color sets. Each MUST have both Any Appearance and Dark Appearance variants.

**Agent colors:**
- `ClaudeBlue` — blue used for Claude identity
- `CodexPurple` — purple used for Codex identity

**Semantic status colors:**
- `StatusActive` — green; connected and running
- `StatusPaused` — orange; paused by user
- `StatusWarning` — orange/amber; needs attention
- `StatusDanger` — red; error, disconnected, destructive

**Accent color:**
- `AccentColor` — use system accent color for standard controls. Do NOT force custom accent globally. Agent colors only for agent-specific elements.

**Rules:**
- Replace every `.blue` meaning "Claude" → `Color("ClaudeBlue")`
- Replace every `.purple` meaning "Codex" → `Color("CodexPurple")`
- Replace every `.green`/`.orange`/`.red` carrying status meaning → semantic name
- Standard SwiftUI controls use system accent — do not override
- Background tints use agent/status color at defined opacity (see DS-3)
- No state may be communicated by color alone. Every colored indicator must have an accompanying text label or SF Symbol

## DS-2: TYPOGRAPHY SCALE

Define as `ViewModifier` or `Font` extensions in a new `Typography.swift`:

```swift
// Type roles — use these everywhere, never ad-hoc .font() calls
enum Type {
    /// .title3.weight(.semibold) — Tab headings, card group titles
    static let sectionTitle: Font = .title3.weight(.semibold)
    /// .headline — Card headers, dialog titles, sidebar section headers
    static let heading: Font = .headline
    /// .callout — Primary content text, descriptions
    static let body: Font = .callout
    /// .caption — Timestamps, counts, badge labels, footer text
    static let caption: Font = .caption
    /// .caption.monospaced() — File paths, code, version hashes
    static let mono: Font = .caption.monospaced()
    /// .callout.monospacedDigit() — File counts, byte sizes in body text
    static let numericBody: Font = .callout.monospacedDigit()
    /// .caption.monospacedDigit() — Counts in badges, timestamps, table numerics
    static let numericCaption: Font = .caption.monospacedDigit()
}
```

**Rules:**
- Never use `.title` or `.title2` — too large for a utility app
- All numeric data uses `.monospacedDigit()`
- File paths always use `Type.mono` + `.truncationMode(.middle)`
- Right-align all numeric table columns
- Secondary text: `Type.body` + `.foregroundStyle(.secondary)`
- Audit every `.font()` call and map to a named role

## DS-3: OPACITY SCALE

```swift
enum Opacity {
    static let rowTint: Double = 0.04      // Agent color on table rows
    static let badgeFill: Double = 0.12    // Badge/chip backgrounds
    static let hoverHighlight: Double = 0.06 // Hover state on cards/rows
    static let disabled: Double = 0.5      // Disabled content
    static let scrim: Double = 0.3         // Overlay behind popovers
}
```

Dark mode note: 0.04 and 0.12 may need conditional adjustment — light tints are more visible on dark backgrounds.

## DS-4: SHADOW PRESETS

```swift
extension View {
    func cardElevation() -> some View {
        self.shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
    func cardHoverElevation() -> some View {
        self.shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
    func popoverElevation() -> some View {
        self.shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
    func toastElevation() -> some View {
        self.shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}
```

## DS-5: ANIMATION PRESETS

```swift
enum Anim {
    static let stateChange: Animation = .snappy           // Pause/resume, connect/disconnect
    static let structural: Animation = .spring            // Layout changes, expand/collapse
    static let entrance: Animation = .spring(duration: 0.4) // Sheet/popover/toast appearance
    static let micro: Animation = .spring(duration: 0.2)    // Hover, selection, badge tick
    
    /// Use when accessibilityReduceMotion is true
    static let none: Animation = .spring(duration: 0)
    
    /// Helper that respects reduce motion
    static func effective(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? none : animation
    }
}
```

**Rules:**
- Every `withAnimation` and `.animation` call uses a named preset
- Every animation checks `@Environment(\.accessibilityReduceMotion)` and falls back to `Anim.none`
- No `.easeInOut`, `.easeIn`, `.easeOut`, or `.linear` anywhere
- Entry transitions: `.move(edge: .leading)` forward, `.move(edge: .trailing)` back
- Numeric count changes: `.contentTransition(.numericText())` on every count label

## DS-6: BADGE COMPONENT

Create `Badge.swift` — one unified component replacing all inline capsule/pill patterns:

```swift
struct Badge: View {
    enum Variant { case info, success, warning, danger, neutral }
    enum Size { case compact, standard, prominent }
    
    let label: String
    let variant: Variant
    var size: Size = .standard
    
    var body: some View {
        // .compact = dot only (6pt), no text
        // .standard = dot (6pt) + caption text
        // .prominent = dot (10pt) + body text
        // All use: Capsule(), horizontal 6 / vertical 2 padding
        // Background: variant color @ Opacity.badgeFill
        // Foreground: variant color full
        // Font: Type.caption.weight(.medium) (.standard), Type.body (.prominent)
        // MUST include .accessibilityLabel(label)
    }
}
```

**Variant colors:**
- `.info` → ClaudeBlue or CodexPurple (agent context)
- `.success` → StatusActive
- `.warning` → StatusPaused
- `.danger` → StatusDanger
- `.neutral` → .secondary

Migrate ALL existing StatusBadge, AgentBadge, inline capsules, and connection indicators to use `Badge`.

## DS-7: EMPTY STATE RULES

Every empty state must answer: (1) What would be here? (2) Why is it empty? (3) What to do next?

Three levels:
- **Full-surface**: `ContentUnavailableView` with icon + title + description + action button. For entire tab/pane empty
- **Section**: Inline text + action button, no icon. For section-level empty (e.g., Smart Mailbox section)
- **Inline**: `.foregroundStyle(.secondary)` text only. For empty list within a section

Differentiate:
- Not configured: "Connect Claude to start monitoring access. You'll see a summary here once connected."
- Configured but empty: "Waiting for activity…" with subtle pulse
- Filtered empty: "No files match the current filters." [Clear Filters]
- Feature-dependent: "Manifold tracks file versions during Tracked Work Blocks. Start a work block to begin versioning."
- Selection-dependent: "Select a message to read it here."

Icons: use relevant feature SF Symbol at ~48pt (full-surface) or ~32pt (section). `.foregroundStyle(.secondary)`.

## DS-8: LOADING STATES

- Never show empty content followed by data appearing. Show loading indicator first
- `ProgressView()` with `.controlSize(.small)` for inline
- `ProgressView("Loading…")` with descriptive text for full-surface
- Show what's happening: "Scanning 247 files…" not just a spinner
- Time estimates for operations > 5 seconds

## DS-9: ERROR BANNER

Replace catch-all `store.lastError` string banner with categorized system:

| Category | Style | Duration | Action |
|----------|-------|----------|--------|
| Connection | Warning (orange) | Persistent | "Retry" button |
| Permission | Warning (orange) | Persistent | "Open System Settings" |
| Database | Danger (red) | Persistent | "Restart Manifold" |
| Network/email | Info (blue) | 10s auto-dismiss | "Retry" per account |
| Validation | Warning (orange) | 10s | Inline guidance |

Structure: headline (human-readable) + details (disclosure group for technical info) + action button + dismiss ✕.
Never expose raw Swift errors. Announce to VoiceOver on appearance.

## DS-10: CONTEXT MENUS

Every list/table row must have a context menu:

| Row type | Required items |
|----------|---------------|
| Source row | Reveal in Finder, Copy Path, View Activity, Remove from Manifold |
| File row | Open, Reveal in Finder, Copy Path, View Version History, Share with [Agent] |
| Domain row | View Emails for Domain, Copy Domain, View Activity |
| Email row | Copy Subject, Share with [Agent] |
| Sidebar source | Reveal in Finder, View Activity, Remove |
| Sidebar email account | Sync Now, Account Details, Remove |

"[Agent]" = currently focused agent (Claude or Codex).

## DS-11: UNDO TOASTS

- Position: bottom-center of content area, 16pt from bottom
- Width: max 400pt, hug content
- Animation: slide up with `Anim.entrance`, auto-dismiss 5 seconds with fade
- Stacking: new toast replaces previous (no overlap)
- Accessibility: announced to VoiceOver
- ⌘Z: `UndoManager` integration for narrowing actions

## DS-12: DRAG AND DROP

| Source → Target | Behavior |
|----------------|----------|
| Finder folder → Files sidebar | Opens Review & Update Access sheet with folder pre-selected |
| Finder file → Files list | Opens Review sheet with parent folder |
| File row → Finder | Reveals file (copies if ⌥ held) |

---

# DEFINITION OF DONE

Every surface must pass this matrix before it's considered complete. Verify each check.

**States:** empty, loading, error, populated, selection, hover, focus, disabled
**Appearance:** light mode, dark mode, Increase Contrast, Reduce Motion
**Input:** keyboard-only (Tab order logical), VoiceOver (labels + grouping), trackpad/mouse (click + right-click + hover)
**Layout:** minimum width 780pt (no clipping), full screen, MacBook notch (menu bar icon accessible)
**Persistence:** relaunch restores selected tab, sidebar selection, inspector state, window position via `@SceneStorage`

---

# EXECUTION BACKLOG

Work through these phases in order. Phase A MUST complete before B–D. Within B–D, items are independent unless noted.

---

## PHASE A — FOUNDATION

Complete these shared primitives first. They prevent repainting surfaces twice.

### A-01: Asset catalog and named colors
Create `Assets.xcassets` per DS-1. Replace every hardcoded color literal (40+ files). Grep to verify zero `.blue`/`.purple`/`.green`/`.orange`/`.red` semantic literals remain. Test light mode, dark mode, Increase Contrast.

### A-02: App icon design
Design a custom macOS app icon at 1024×1024. Generate all required sizes (16–1024 @1x/@2x). Must read at 16px, work on light+dark desktop backgrounds, communicate protection/visibility/trust. Place in `AppIcon.appiconset`.

### A-03: Menu bar custom icon
Design monochrome template image at 18×18pt (36×36px @2x). Must be recognizable among 15+ menu bar icons. System manages tint. Place in `MenuBarIcon.imageset`. Update `ManifoldApp.swift` label.

### A-04: Typography scale
Implement DS-2 type scale as shared extensions. Audit and replace every `.font()` call in 78+ files. All numerics use `.monospacedDigit()`. All paths use `Type.mono` + `.truncationMode(.middle)`.

### A-05: Design token completion
Implement DS-3 (opacity), DS-4 (shadows), DS-5 (animations). Replace all inline values. Grep to verify zero `.easeInOut`/`.easeIn`/`.easeOut`/`.linear` remain. Every animation checks `accessibilityReduceMotion`.

### A-06: Unified badge component
Build `Badge.swift` per DS-6. Migrate ALL existing StatusBadge, AgentBadge, inline capsules, and connection indicators. Every badge has `.accessibilityLabel`. Visual consistency across all surfaces.

### A-07: Empty state overhaul
Implement DS-7 across all ~11 empty state locations. Full-surface vs. section vs. inline levels. Conditional differentiation (not configured / empty / filtered). Smart Mailbox section uses section-level, not full-surface. All copy follows voice rules.

### A-08: Loading state implementation
Implement DS-8. No flash of empty on app launch. Source enumeration shows scanning indicator. Email sync shows per-account progress. Content search shows "Searching X files…". All loading text descriptive.

### A-09: Error banner system
Replace catch-all banner per DS-9. Categorize: connection, permission, database, network, validation. Each has banner style, duration, recovery action. No raw Swift strings. Non-critical auto-dismiss at 10s. VoiceOver announced.

### A-10: Accessibility baseline
Systematic pass: `.accessibilityLabel` on every interactive control and status indicator. `.accessibilityElement(children: .contain)` on card containers. `@FocusState` + `.defaultFocus()` on every sheet. Tab order verified in ReviewAccessSheet and EmailAccountSetupView. Dynamic Type tested at 2 sizes above default. Zero color-only signaling instances.

### A-11: Localization infrastructure
Extract all user-facing strings into `.xcstrings` catalog. Use `String(localized:)` or `LocalizedStringKey`. Verify layout with pseudo-localization (30% longer strings). Do NOT translate — English only for v1. Depends on: A-07 and A-09 (copy finalized first).

### A-12: Content design rules
The content design rules are defined in the CONTENT VOICE section above and in DS-7/DS-8/DS-9. Verify all copy written in A-07/A-08/A-09 follows these rules before proceeding to Phase B. This is a review checkpoint, not a code task.

---

## PHASE B — CORE SURFACES

Polish each surface using the foundation from Phase A. Phase A must be complete.

### B-01: Overview tab polish
- Cards: hover state with `Shadow.cardHover` + `Anim.micro`. Equal minimum height for both agent cards
- CTA: hide "Start Tracked Work Block" when no sources configured. Animate CTA → banner transition without layout jump
- Empty state: warm contextual copy per DS-7
- Verify against DoD matrix

### B-02: Files tab polish
- Sidebar: source dots use focused agent color (not always blue). "Recently Modified"/"AI-Touched" show counts with `Type.numericCaption`
- Table: Items/Size columns right-aligned. "✨" → SF Symbol `sparkles`. Sort persists per source via `@SceneStorage`
- Versions: "No Versions" empty state explains when versions appear
- Content search: list layout for >5 results (not horizontal card scroll)
- Verify against DoD matrix

### B-03: Emails tab polish
- Category icons: SF Symbols (building.2, gearshape.2, person, eye.slash) not emoji
- Section headers show domain counts
- Sensitivity change animates rows between sections with `Anim.structural`
- Reading pane empty: "Select a message to read it here" + `envelope.open`
- "Share with Cowork" → "Share with Claude"/"Share with Codex" based on agent focus
- Search tokens use `Badge` component styling
- Plain text emails in monospace
- HTML emails block remote images by default with "Load Remote Images" button
- Verify against DoD matrix

### B-04: Settings polish
- General (currently 22 lines): add default agent focus picker, keyboard shortcuts reference, menu bar toggle, data & privacy link
- AI Apps: "Test Connection" button per agent, "Last connected" timestamp, MCP config path accessible
- Mail: sync status per account, reorderable accounts
- Storage: "Clean Up" explains what it does before action, "Verify Database" shows clear result badge
- Move version number to About window
- Verify against DoD matrix

### B-05: Onboarding polish
- Step indicator: filled circles connected by lines with labels, not plain 8pt dots
- Welcome: "Control what AI can see on your Mac" (not "Welcome to Manifold")
- Connect Apps: MCP install shows progress text, errors inline with retry, skip less prominent than continue
- Add Data: added sources listed with remove buttons, email marked as optional
- Finish: configured items with ✓ + skipped items with neutral indicator, button says "Get Started"
- Window close re-appears on relaunch unless step 2+ completed (`@AppStorage("hasCompletedOnboarding")`)
- Transitions respect `accessibilityReduceMotion`

### B-06: About window
Create `AboutView`: app icon at ~64pt, "Manifold", version + build, copyright, tagline. Links: website, privacy policy, acknowledgements. Register in `ManifoldApp.swift`. Small and calm.

### B-07: Window restoration
`@SceneStorage` for: selected tab, sidebar selection per tab, inspector visibility, agent focus, window position/size. Test: close app → relaunch → verify everything matches.

### B-08: EmailAccountSetupView overhaul
The app's most complex modal (838 lines):
- Step indicator with labels: "Email → Provider → Credentials → Connect → Done"
- Auto-detect timeout at 5s with manual override
- Password show/hide toggle
- Connection steps show time estimates
- Errors specific and actionable (e.g., "Gmail requires an App Password if 2FA is enabled")
- OAuth buttons use provider brand colors/icons
- Email TextField auto-focused on appear
- Tab cycles through fields
- Back preserves data at every step

### B-09: Sheets and modals consistency
- ReviewAccessSheet: Files ↔ Emails tab crossfade, checkbox → "What's Changing" entrance animation, footer sticky with 20+ items
- ReviewChangesSheet: collapsible sections, promote progress bar, brief success state before dismiss
- ShareWithCoworkSheet: "Share with Claude/Codex" naming, agent picker if both connected, success feedback
- All sheets: Enter → primary CTA, Escape → cancel

### B-10: Trust and privacy UX
- Data locality: Settings → Data & Privacy: "All data stays on your Mac. Manifold never sends your files or emails to any server."
- Access explanation: file access indicators have tooltip/popover explaining which policy granted access and when
- Destructive actions: source removal dialog states consequences for agents and version history
- Remote images: blocked by default with "Load Remote Images" banner in HTMLEmailView
- Storage: "Clean Up" explains what it removes. Retention visible per category

---

## PHASE C — NATIVE FEEL

Platform conventions and system integration. Phases A and B should be complete.

### C-01: Menu bar and command audit
Complete all standard macOS menus:
- File: "Add Folder…", "Add Email Account…"
- Edit: standard text commands in all text fields, Undo reflects app-level undo
- View: "Toggle Sidebar", tab switching shortcuts
- Window: Minimize, Zoom, Bring All to Front, main window access
- Help: "Manifold Help", system search field
- Every keyboard shortcut (⌘⇧R, ⌘⇧W, ⌘⇧P, etc.) must appear in a menu

### C-02: Context menus on all rows
Implement DS-10 on every list/table row. "Share with [Agent]" reflects focused agent. VoiceOver accessible (VO+Shift+M).

### C-03: Drag and drop
Implement DS-12. Finder folder → sidebar opens Review sheet. File row → Finder reveals. Drop target highlighting with `Anim.micro`. Register `.onDrop(of: [.fileURL])` on sidebar.

### C-04: Keyboard polish
- Tab order logical everywhere (left→right, top→bottom)
- Escape priority: command palette > sheet > popover
- ⌘W closes window, keeps app running (menu bar accessible)
- Focus ring visible on every focused element
- j/k email navigation (verify existing), Space to scroll reading pane
- Full keyboard walkthrough: all tabs, sheets, agent focus, no mouse

### C-05: Full screen and layout edge cases
- Full screen: sidebar functional, menu bar extra accessible
- Split screen with Safari/Terminal
- Notch: menu bar icon in overflow area on MacBook Pro
- Minimum width 780pt: no clipping, no overlap
- ⌘N prevented from creating duplicate windows

### C-06: Undo system unification
Implement DS-11. Consistent toast design everywhere. New toast replaces previous. VoiceOver announced. ⌘Z via UndoManager for narrowing actions.

### C-07: Proxy icon and title bar
- Overview: title "Manifold"
- Files with source selected: title shows source name, proxy icon draggable to Finder
- Emails: title "Manifold — Mail" or similar
- Verify with Liquid Glass toolbar on macOS 26

---

## PHASE D — DELIGHT (implement as time allows, prioritize D-01 and D-03)

### D-01: DiffView upgrades
Syntax highlighting for Swift, TypeScript, JSON, YAML, Markdown. Word-level diff within changed lines. Dynamic line number width. "Copy Diff" button (unified format). Lazy rendering for 5000+ line diffs.

### D-02: Command palette improvements
Fuzzy matching ("rev" → "Review Access"). 3 most recent commands when search empty. SF Symbol icon per command. "X results" label when filtered.

### D-03: Domain favicons (privacy-safe)
Fetch directly from `https://domain.com/favicon.ico` — NOT Google's endpoint. Opt-in or disclosed in Settings → Privacy. Cache locally, fetch once per domain. Fallback: globe SF Symbol. No fetch without user awareness.

### D-04: File type-specific icons
Replace generic `doc` icon with `NSWorkspace.shared.icon(forFileType:)`. Native file type icons at consistent size, not blurry @2x.

### D-05: Email search token colors
Color-code tokens: "from:" = agent blue, "to:" = green, dates = orange. Use `Badge` component styling.

### D-06: Performance edge case testing
100+ sources, 10K+ emails, 50+ smart mailboxes, 5000-line diffs, deeply nested paths. `.truncationMode(.middle)` everywhere for paths.

### D-07: Export capabilities
Audit log export: clean CSV or JSON. Add "Export Current Policy": human-readable summary of agent access. Standard macOS save panel.

---

## VERIFICATION CHECKLIST

After each phase, verify:

- [ ] Every surface passes the Definition of Done matrix
- [ ] Zero hardcoded color literals for semantic meaning (grep `.blue`, `.purple`, `.green`, `.orange`, `.red`)
- [ ] Zero legacy animation curves (grep `.easeInOut`, `.easeIn`, `.easeOut`, `.linear`)
- [ ] Zero orphan `.font()` calls not using Type scale (grep for `.font(\.` not preceded by Type.)
- [ ] Zero "Cowork", "session" (lowercase), "folder" (when meaning source), "sender" (when meaning domain) in user-facing strings
- [ ] Every badge uses the unified Badge component
- [ ] Every empty state answers: what, why, what next
- [ ] Every error has a recovery action
- [ ] Build succeeds with zero warnings
- [ ] App launches without flash of empty content
- [ ] ⌘W closes window, app stays running in menu bar
- [ ] Relaunch restores all UI state
- [ ] VoiceOver can navigate every surface
- [ ] Keyboard can reach every action
