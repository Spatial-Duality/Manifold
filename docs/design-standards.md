# Manifold — Design Standards

> **What this is**: The shared design system that must exist before surface-by-surface polish begins. Every token, component spec, copy rule, and QA requirement lives here. This is the foundation that prevents rework.
>
> **How to use**: Implement everything in this document during Phase A of the backlog. Then reference it as the source of truth during Phases B–D. If a backlog item says "per DESIGN-STANDARDS," this is where to look.

---

## 1. COLOR SYSTEM

### 1.1 Asset catalog structure

Create `Assets.xcassets` with the following named color sets. Each must define both Any Appearance and Dark Appearance variants.

**Agent colors** (brand identity):
- `ClaudeBlue` — the blue used for Claude identity throughout the app
- `CodexPurple` — the purple used for Codex identity throughout the app

**Semantic status colors** (meaning, not decoration):
- `StatusActive` — green; agent connected and running
- `StatusPaused` — orange; agent paused by user
- `StatusWarning` — orange/amber; needs attention but not broken
- `StatusDanger` — red; error, disconnected, destructive action

**Accent color**:
- `AccentColor` — use the system accent color for standard controls (buttons, toggles, selections). Do NOT force a custom accent color globally. Use agent colors only for agent-specific elements.

### 1.2 Color usage rules

- Replace every `.blue` literal that means "Claude" with `Color("ClaudeBlue")`
- Replace every `.purple` literal that means "Codex" with `Color("CodexPurple")`
- Replace every `.green` / `.orange` / `.red` that carries status meaning with the semantic name
- Standard SwiftUI controls (buttons, pickers, toggles) use the system accent color — do not override
- Background tints use the agent/status color at defined opacity levels (see §3 Opacity Scale)
- Test every named color in: light mode, dark mode, Increase Contrast, color filters for deuteranopia

### 1.3 Color-only signaling prohibition

No state may be communicated by color alone. Every colored indicator (dot, chip, badge, row tint) must have an accompanying text label or SF Symbol that conveys the same information without color.

---

## 2. TYPOGRAPHY SCALE

### 2.1 Type roles

Define these as `ViewModifier` or `Font` extensions, not ad-hoc per-view:

| Role | Font | Use |
|------|------|-----|
| `Type.sectionTitle` | `.title3.weight(.semibold)` | Tab headings, card group titles |
| `Type.heading` | `.headline` | Card headers, dialog titles, sidebar section headers |
| `Type.body` | `.callout` | Primary content text, descriptions |
| `Type.secondary` | `.callout` + `.foregroundStyle(.secondary)` | Supporting text, explanations |
| `Type.caption` | `.caption` | Timestamps, counts, badge labels, footer text |
| `Type.mono` | `.caption.monospaced()` | File paths, code, version hashes, dates in tables |
| `Type.numericBody` | `.callout.monospacedDigit()` | File counts, email counts, byte sizes in body |
| `Type.numericCaption` | `.caption.monospacedDigit()` | Counts in badges, timestamps, table numerics |

### 2.2 Typography rules

- Never use `.title` or `.title2` — too large for a utility app
- All numeric data uses `.monospacedDigit()` — counts, sizes, times, percentages
- File paths always use `Type.mono` with `.truncationMode(.middle)` — show root + filename
- Right-align all numeric table columns
- Audit every `.font()` call and map it to a role from §2.1

---

## 3. OPACITY SCALE

Named opacity values to replace inline magic numbers:

| Token | Value | Use |
|-------|-------|-----|
| `Opacity.rowTint` | 0.04 | Agent color background tint on table rows |
| `Opacity.badgeFill` | 0.12 | Badge/chip background behind text |
| `Opacity.hoverHighlight` | 0.06 | Hover state on cards and rows |
| `Opacity.disabled` | 0.5 | Disabled content and controls |
| `Opacity.scrim` | 0.3 | Overlay behind popovers and command palette |

Dark mode note: 0.04 and 0.12 tints may need adjustment in dark mode (light colors on dark backgrounds are more visible). Define these in the asset catalog or conditionally.

---

## 4. SHADOW PRESETS

| Token | Value | Use |
|-------|-------|-----|
| `Shadow.card` | `color: .black.opacity(0.08), radius: 3, y: 1` | Agent policy cards, overview cards |
| `Shadow.cardHover` | `color: .black.opacity(0.12), radius: 5, y: 2` | Hovered cards |
| `Shadow.popover` | `color: .black.opacity(0.15), radius: 8, y: 4` | Popovers, command palette |
| `Shadow.toast` | `color: .black.opacity(0.10), radius: 4, y: 2` | Undo toasts, notification banners |

Implement as `ViewModifier` extensions: `.cardElevation()`, `.cardHoverElevation()`, etc.

---

## 5. ANIMATION PRESETS

Named animations replacing all inline `.easeInOut` and custom spring definitions:

| Token | Value | Use |
|-------|-------|-----|
| `Anim.stateChange` | `.snappy` | Pause/resume, connect/disconnect, toggle states |
| `Anim.structural` | `.spring` | Layout changes, section expand/collapse |
| `Anim.entrance` | `.spring(duration: 0.4)` | Sheet/popover/toast appearance |
| `Anim.micro` | `.spring(duration: 0.2)` | Hover, selection highlight, badge count tick |
| `Anim.none` | `.spring(duration: 0)` | Used when `accessibilityReduceMotion` is true |

### 5.1 Animation rules

- Every `withAnimation` and `.animation` call uses a named preset from §5
- Every animation checks `@Environment(\.accessibilityReduceMotion)` and falls back to `Anim.none`
- Entry transitions: `.move(edge: .leading)` for forward navigation, `.move(edge: .trailing)` for back
- Cross-fade transitions: `.opacity` combined with `.transition(.asymmetric(...))`
- Numeric count changes: `.contentTransition(.numericText())` on every count label
- No `.easeInOut`, `.easeIn`, `.easeOut`, or `.linear` anywhere in the codebase

---

## 6. BADGE / PILL COMPONENT

One unified `Badge` component replaces all inline capsule implementations:

### 6.1 Variants

| Variant | Background | Foreground | Use |
|---------|-----------|------------|-----|
| `.info` | agent/blue @ `Opacity.badgeFill` | agent/blue | Connection status, neutral info |
| `.success` | `StatusActive` @ `Opacity.badgeFill` | `StatusActive` | Active, connected, granted |
| `.warning` | `StatusPaused` @ `Opacity.badgeFill` | `StatusPaused` | Paused, needs attention |
| `.danger` | `StatusDanger` @ `Opacity.badgeFill` | `StatusDanger` | Error, disconnected, denied |
| `.neutral` | `.secondary` @ `Opacity.badgeFill` | `.secondary` | Inactive, disabled, default |

### 6.2 Shared properties

All variants use:
- Padding: horizontal 6, vertical 2
- Shape: `Capsule()`
- Font: `Type.caption` with `.weight(.medium)`
- Must include `.accessibilityLabel` describing the state in words

### 6.3 Size variants

- `.compact` — dot only (6pt circle), no text. For tight table cells
- `.standard` — dot + text label. Default
- `.prominent` — 10pt dot + `Type.body` text. For card headers

---

## 7. EMPTY STATE COMPONENT

### 7.1 Rules

Every empty state must answer three questions:
1. **What would be here?** — describe the content that will appear
2. **Why is it empty?** — explain the current state without blame
3. **What to do next?** — provide a single clear action

### 7.2 Levels

| Level | Pattern | When to use |
|-------|---------|-------------|
| Full-surface | `ContentUnavailableView` with icon, title, description, action button | Entire tab or pane is empty |
| Section | Inline text + action button, no icon | A section within a populated view is empty (e.g., Smart Mailbox section) |
| Inline | `.foregroundStyle(.secondary)` text only | A list/table within a section is empty but the section has other content |

### 7.3 Icon rules

- Use the relevant tab or feature SF Symbol, not generic icons like `antenna.radiowaves.left.and.right`
- Render at ~48pt for full-surface, ~32pt for section
- Use `.foregroundStyle(.secondary)` — empty states should be calm, not attention-seeking

### 7.4 Conditional empty states

Differentiate between:
- **Not configured**: "Connect Claude to start monitoring access." [Connect →]
- **Configured but no data yet**: "Waiting for activity…" with subtle pulse
- **Configured and empty**: "No files match this filter." [Clear Filters]

---

## 8. LOADING STATE COMPONENT

### 8.1 Rules

- Never show empty content followed by data appearing (flash of empty). Show a loading indicator instead
- Use `ProgressView()` with `.controlSize(.small)` for inline indicators
- Use `ProgressView("Loading…")` with descriptive text for full-surface loads
- Show what's happening: "Scanning 247 files…" not just a spinner
- Estimated time for operations > 5 seconds: "This may take a minute for large accounts"

### 8.2 Skeleton pattern (optional)

For list/table views, consider redacted placeholder rows during load:
```swift
ForEach(0..<5) { _ in PlaceholderRow() }
    .redacted(reason: .placeholder)
```

---

## 9. ERROR BANNER COMPONENT

### 9.1 Error categories

| Category | Banner style | Duration | Recovery action |
|----------|-------------|----------|-----------------|
| Connection | Warning (orange) | Persistent until resolved | "Retry" button |
| Permission | Warning (orange) | Persistent | "Open System Settings" link |
| Database | Danger (red) | Persistent | "Restart Manifold" suggestion |
| Network (email sync) | Info (blue) | 10 seconds auto-dismiss | "Retry" per account |
| Validation | Warning (orange) | 10 seconds | Inline guidance |

### 9.2 Banner structure

- **Headline**: Human-readable summary (never a raw Swift error string)
- **Details**: Disclosure group with technical details (for support/debugging)
- **Action**: At least one recovery button
- **Dismiss**: ✕ button, plus auto-dismiss timer for non-critical errors
- **Accessibility**: Announced to VoiceOver on appearance

### 9.3 Error copy rules

- Say what happened, not what failed internally
- Say what the user can do about it
- Never blame the user
- Never expose type names, module paths, or error codes as primary text

---

## 10. CONTENT DESIGN RULES

### 10.1 Voice

Manifold's voice is **calm, factual, and respectful of the user's intelligence**.

- Say what happened
- Say why the user is seeing it
- Say what to do next
- Prefer direct language over playful language
- Never blame the user
- Never use exclamation marks in error or warning copy
- Avoid "Oops", "Uh oh", "Something went wrong" — these are filler, not information

### 10.2 Label conventions for the current product model

- "Pause Access" / "Resume Access" — not a toggle, a button
- "Review & Update Access" — the sheet name
- "Start Tracked Work Block" — not "session"
- "Claude" / "Codex" — agent names, never "Cowork" in user-facing text
- "Sources" — not "folders" (a source is a monitored folder)
- "Domains" — not "senders" (email access is domain-scoped)

### 10.3 Empty state copy patterns

- "Connect [agent] to start monitoring access. You'll see a summary here once connected." — not configured
- "No files match the current filters." — filtered empty
- "Manifold tracks file versions during Tracked Work Blocks. Start a work block to begin versioning." — feature-dependent empty
- "Select a message to read it here." — selection-dependent empty

### 10.4 Destructive action copy patterns

- Always state what will happen: "Remove web-app from Manifold? Claude and Codex will immediately lose access to 247 files in this folder."
- State reversibility: "You can re-add this folder later, but version history will start fresh."
- Use `.destructive` button role for the action, `.cancel` for dismissal

---

## 11. UNIVERSAL DEFINITION OF DONE MATRIX

Every major surface must pass this matrix before it's considered polished. Document surface-specific exceptions only.

### 11.1 State coverage

| State | Verification |
|-------|-------------|
| Empty | Shows appropriate empty state per §7 |
| Loading | Shows loading indicator per §8 |
| Error | Shows error banner per §9 with recovery action |
| Populated | Content renders correctly with realistic data |
| Selection | Selected item highlighted, detail pane updates |
| Hover | Interactive elements show hover state |
| Focus | Keyboard focus ring visible on focused element |
| Disabled | Disabled controls use `Opacity.disabled`, not hidden |

### 11.2 Appearance

| Check | Verification |
|-------|-------------|
| Light mode | All colors, text, and tints render correctly |
| Dark mode | All named colors have dark variants; tints remain visible |
| Increased Contrast | Badges, dots, and tints remain distinguishable |
| Reduce Motion | All animations respect the preference; no motion except layout |

### 11.3 Input methods

| Check | Verification |
|-------|-------------|
| Keyboard only | Every action reachable via keyboard; Tab order is logical |
| VoiceOver | Every element has a label; groups are logical; state changes announced |
| Trackpad/mouse | Click, right-click, hover all work correctly |

### 11.4 Layout

| Check | Verification |
|-------|-------------|
| Minimum width (780pt) | No clipping, no overlap, no horizontal scroll |
| Full screen | Sidebar, content, and detail all function correctly |
| Notch (MacBook Pro) | Menu bar icon accessible from overflow if pushed behind notch |

### 11.5 Persistence

| Check | Verification |
|-------|-------------|
| Relaunch restoration | Selected tab, sidebar selection, inspector state, window position all restored via `@SceneStorage` |

### 11.6 Review artifacts required per phase

For each phase in the backlog, the implementer must produce:
1. Before/after screenshots (light and dark mode)
2. One keyboard-only walkthrough (navigate every action without mouse)
3. One VoiceOver walkthrough (read every element, verify labels and grouping)
4. One narrow-width check (resize to 780pt, verify nothing breaks)

---

## 12. CONTEXT MENU STANDARD

Every list/table row must have a context menu. Minimum items:

| Row type | Required context menu items |
|----------|---------------------------|
| Source row | Reveal in Finder, Copy Path, View Activity, Remove from Manifold |
| File row | Open, Reveal in Finder, Copy Path, View Version History, Share with [Agent] |
| Domain row | View Emails for Domain, Copy Domain, View Activity |
| Email row | Copy Subject, Share with [Agent] |
| Sidebar source | Reveal in Finder, View Activity, Remove |
| Sidebar email account | Sync Now, Account Details, Remove |

The "[Agent]" label reflects the currently focused agent (Claude or Codex).

---

## 13. UNDO SYSTEM STANDARD

### 13.1 Toast design

- Position: bottom-center of the content area, 16pt from bottom edge
- Width: max 400pt, hugging content
- Animation: slide up with `Anim.entrance`, auto-dismiss after 5 seconds with fade
- Stacking: new toast replaces previous (no stacking or overlap)
- Accessibility: announced to VoiceOver on appearance
- Content: "[Action] undone." + "Undo" button

### 13.2 ⌘Z support

- `UndoManager` integration for narrowing actions (source removal, domain removal)
- Keyboard undo support is required where the action model supports it. This standard covers the visual consistency.

---

## 14. DRAG AND DROP STANDARD

| Source → Target | Behavior |
|----------------|----------|
| Finder folder → Files sidebar | Opens Review & Update Access sheet with folder pre-selected |
| Finder file → Files list | Opens Review sheet with parent folder if not already a source |
| File row → Finder | Reveals file in Finder (or copies if held with ⌥) |
