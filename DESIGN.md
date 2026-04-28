# Design System — Manifold

## Product Context
- **What this is:** Native macOS app for controlled AI agent access and file recovery
- **Who it's for:** Developers and early AI users who want zero friction
- **Space/industry:** AI agent access control, file versioning
- **Project type:** macOS utility (menu bar + main window)

## Design Position: Deeply Native

Manifold is a native macOS 26 app built with Liquid Glass as its primary design language. The platform is the design system. Not a custom-skinned app that happens to run on macOS.

Rationale: Manifold's philosophy is curated software. The highest expression of curation on macOS is using the platform's own materials with precision and taste. The best Mac apps (Things, Fantastical, Apple's own) are deeply native with one or two distinctive moments.

## Typography

- **All UI text:** SF Pro via system font stack
- **Monospace (code, diffs, file paths, hashes):** SF Mono via system monospace stack
- **No custom fonts in the product.** SF Pro is the typeface.

### Type Scale (`Typ` enum in `Components/DesignTokens.swift`)

| Token | System Font | Use |
|-------|-------------|-----|
| `sectionTitle` | `.title3.weight(.semibold)` | Tab headings, card group titles |
| `heading` | `.headline` | Card headers, dialog titles, sidebar section headers |
| `body` | `.callout` | Primary content text, descriptions |
| `caption` | `.caption` | Timestamps, counts, badge labels, footer text |
| `mono` | `.caption.monospaced()` | File paths, code, version hashes |
| `numericBody` | `.callout.monospacedDigit()` | File counts, byte sizes in body text |
| `numericCaption` | `.caption.monospacedDigit()` | Badge counts, timestamps, table numerics |

### Typography Weights

Three weights only. No bold. No light.

| Weight | Use |
|--------|-----|
| Regular (default) | Body text, descriptions, secondary content |
| Medium (`.weight(.medium)`) | Labels, section headers, source names, email senders |
| Semibold (`.weight(.semibold)`) | Screen titles in onboarding/welcome only |

## Colour

- **Approach:** System semantic tokens only
- **All functional colours:** `.blue`, `.purple`, `.green`, `.orange`, `.yellow`, `.red`, `.secondary`, `.tertiary`, `.quaternary`
- **Agent colours:** Claude = `.blue`, Codex = `.purple`
- **Status:** Active = `.green`, Paused = `.orange`, Warning = `.yellow`, Danger = `.red`
- **No custom hex palette for UI.** System tokens adapt automatically to light/dark and accessibility settings.

### Agent Identity Pattern

Agent identity is communicated through content, not decoration:
- 10pt filled circle in agent color (header row of agent cards)
- Card background tint at `Opacity.rowTint` (0.04)
- Text badge ("Active" / "Paused") in agent color at `Opacity.badgeFill` (0.12)
- No colored borders. No colored header bars. The dot IS the identity.
- In tables: column header names the agent ("Claude" / "Codex"), row tinting at 0.04 for granted items.

### Opacity Scale (`Opacity` enum)

| Token | Value | Use |
|-------|-------|-----|
| `rowTint` | 0.04 | Subtle row background for granted/active items |
| `badgeFill` | 0.12 | Badge/chip background fill |
| `hoverHighlight` | 0.06 | Hover state on interactive elements |
| `disabled` | 0.5 | Disabled element overlay |
| `scrim` | 0.3 | Command palette overlay background |

## Brand Mark

`{ | }` — the brand mark embodies the product thesis as a glyph. The vertical
bar is content authority (what flows through Manifold). The curly braces are
the trust boundary that scopes it. The bar between braces IS the product.

Live in `brand/` (sibling to `design/`). The folder is the canonical source;
DESIGN.md references it.

### Static variants

| Variant | File | Use |
|---------|------|-----|
| Dark | `brand/mark-dark.svg` | Dark backgrounds; primary identity |
| Light | `brand/mark-light.svg` | Light backgrounds (warm ink palette) |
| Mono | `brand/mark-mono.svg` | Single-color contexts (favicon, embeds, social previews) |
| Wordmark | `brand/wordmark-dark.svg` | Full lockup `{ \| } MANIFOLD` |
| Compact logo (no halos) | `brand/logo-compact.html` | Sidebar, footer, secondary contexts |

### Title sequence

Animated reveal: particle morph between slot states (`{ \| }` ↔ `{ /files }` ↔
`{ /emails }` ↔ `{ /history }`). The morph is structural, not decorative — each
slot is a real Manifold scope, so the animation demonstrates the product.

| Surface | Implementation | File |
|---------|----------------|------|
| In-app splash | SwiftUI `ManifoldTitleSequence` (port of iter-05) | `brand/TitleSequence.swift` |
| Web hero | Canvas + additive blending, 280 particles | `brand/iter-06-canvas.html` |
| Iteration history | Pass-by-pass review with honest reference comparisons | `brand/iteration-log.md` |
| Pre-build research | Direction decisions, technical references | `brand/animation-research.md` |

Both production variants ship. Each fits its render budget: SwiftUI is clean
and inspectable for in-app; Canvas is more cinematic in motion for the first
impression on web.

`prefers-reduced-motion: reduce` automatically applies a static frame on web.
The SwiftUI version respects scene activity (pauses when inactive).

To use in the app target, move `brand/TitleSequence.swift` to
`ManifoldApp/ManifoldApp/Views/Brand/TitleSequence.swift` and add it to the
Xcode project. It's kept in `brand/` until adoption is wired so the brand work
stays self-contained as reference.

### Brand colors (NOT for UI)

The mark and title sequence use specific brand colors. These do NOT appear in
app UI. The macOS app uses Liquid Glass + system semantic colors exclusively
(see "Colour" above). Brand uses these specific hex values.

| Token | Hex | Use |
|-------|-----|-----|
| Brand ink (deep) | `#0A0907` | Brace gradient bottom |
| Brand ink (mid) | `#15140F` | Brace gradient mid; bar fill |
| Brand ink (top) | `#2C2A24` | Brace gradient top |
| Brand warm halo | `#B86A1E` @ 0.18 | Halo behind mark; transit tint during morph |
| Brand cold accent | cool cyan | 1% of particles in title sequence (atom mix) |

Atom color mix ratio in the title sequence: **92% ink / 7% warm / 1% cold**.

If brand hex values appear in SwiftUI UI code, that's a regression. Brand
identity lives in the mark, the wordmark, and the title sequence — never in
buttons, surfaces, or row tints.

## Liquid Glass

### Core Principle
Glass is the navigation layer. Content never uses glass. Do not stack glass on glass.

### SwiftUI API Reference (macOS 26+)

**Glass variants:**
- `Glass.regular` — default translucent glass. Use for most navigation chrome.
- `Glass.clear` — higher transparency. Requires media-rich background.
- `.tint(_ color:)` — adds color tint. Reserve for primary actions only.
- `.interactive()` — iOS only. Do NOT use on macOS.

**Button styles:**
- `.buttonStyle(.glass)` — secondary actions
- `.buttonStyle(.glassProminent)` — primary action (one per screen)

### Automatic Glass (no code needed)
- Sidebar, toolbar, menu bar, window controls — recompile with Xcode 26 and glass appears.
- `NavigationSplitView` sidebar gets floating glass automatically.
- System sheets, alerts, popovers get glass chrome automatically.

### Surface Mapping
| Surface | Treatment |
|---------|-----------|
| Sidebar | Automatic floating glass (NavigationSplitView) |
| Toolbar | Automatic glass (system toolbar). No custom background colors. |
| Command palette | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))` |
| Error banner | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Spacing.standard))` |
| Menu bar panel | Automatic glass (MenuBarExtra .window style) |
| Onboarding modal | System sheet (glass chrome, content non-glass) |
| Agent cards | Non-glass. Agent-color tint at `Opacity.rowTint`. |

### Button Tint Hierarchy
- `.glassProminent` + `.tint(.accentColor)` — Primary hero action (strongest)
- `.glassProminent` — Secondary hero action
- `.glass` — Tertiary actions
- `.bordered` — Inline actions, settings

### Fallback (pre-macOS 26)
```swift
if #available(macOS 26, *) {
    content.glassEffect(.regular, in: shape)
} else {
    content.background(.ultraThinMaterial, in: shape)
}
```

Centralized in `Spacing.swift` via `glassBackground()`, `glassProminentButton()`, `glassButton()` helpers.

### Accessibility
Glass auto-adapts to Reduce Transparency, Increase Contrast, and Reduce Motion.
No extra code needed. System handles all accessibility states.

## Spacing

Base-4 scale. Defined in `Components/Spacing.swift`. No ad-hoc values.

| Token | Value | Use |
|-------|-------|-----|
| `tight` | 4pt | Icon-to-text gaps, inline elements |
| `standard` | 8pt | List row padding, button padding |
| `section` | 12pt | Spacing within a view section |
| `edge` | 16pt | View edge padding |
| `large` | 24pt | Section separation, onboarding |
| `xlarge` | 32pt | Major section separation |

## Layout

- **Shell model:** single `NavigationSplitView` ledger with five destinations in a flat sidebar (⌘1–⌘5): Activity, Access, Mail, Requests, Rules. No per-tab mini-shells.
- **Title ownership:** the detail column sets `.navigationTitle(destination.title)`; the sidebar sets none. Two navigation titles fight and the sidebar's first rows render behind the traffic lights on macOS 26.
- **Sidebar:** flat `List { ForEach … }`, system `Label` rows, `.badge(Text?)` for pending counts. A one-`Section` wrapper renders as a blank column on macOS 26. Column width contract `min 220 / ideal 240 / max 280`.
- **Session chip:** lives only in the status bar. One ambient home for runtime state — never duplicated in the toolbar.
- **Toolbar:** primary action is Start session / Finish session (the toolbar stays populated so macOS does not collapse the title bar alongside a collapsed sidebar). Secondary action is Refresh runtime.
- **Status bar:** honest runtime + session state, with a Reconnect button when the runtime is offline.
- `.navigationSplitViewStyle(.balanced)` throughout.
- Settings is a separate scene (⌘,), 6-tab TabView: General, Agents, Storage, Mail, Rules (global defaults only), Advanced.
- Command palette (⌘K) for keyboard-first control.
- Menu bar panel (MenuBarExtra .window style) with agent status, session strip, pending requests, quick actions.

### Column Widths
| Column | Min | Ideal | Max |
|--------|-----|-------|-----|
| Files sidebar | 220 | 240 | 300 |
| Email sidebar | 220 | 240 | 320 |
| Email message list | 260 | 300 | 450 |
| Inspector | 280 | 360 | 480 |

## Data Tables

- Use SwiftUI `Table` for data-dense listings (Files tab, Sources tab)
- Sortable columns via `KeyPathComparator` bindings
- **Files table columns:** Name (with type icon), Path, Source, Size, Modified, Type
- **Sources table columns:** Name, Path, Items (lazy-counted), Agent access (agent-named)
- Selection drives context menus via `.contextMenu(forSelectionType:)`
- Right-click context menu: Open, Reveal in Finder, Copy Path, Version History
- Filter bar in `.safeAreaInset(edge: .top)` with source picker, name filter, content search

## Context Menus
- Files: Open, Reveal in Finder, Copy Path, Version History
- Sources: Reveal in Finder, Copy Path, View Activity, Remove (destructive)
- Both follow `.contextMenu(forSelectionType:)` for multi-select support

## Corner Radii
| Token | Value | Use |
|-------|-------|-----|
| `small` | 6pt | Inline pills, command row hover |
| `medium` | 10pt | Cards, stat containers |
| `large` | 12pt | Section cards, command palette |

## Icons
- SF Symbols throughout
- No custom icon assets for UI controls
- Custom assets only: app icon

## Motion (`Anim` enum)

| Token | Animation | Use |
|-------|-----------|-----|
| `stateChange` | `.snappy` | Pause/resume, connect/disconnect |
| `structural` | `.spring` | Layout changes, expand/collapse |
| `entrance` | `.spring(duration: 0.4)` | Sheet/popover/toast appearance |
| `micro` | `.spring(duration: 0.2)` | Hover, selection, badge tick |

`Anim.effective(_:reduceMotion:)` respects the Reduce Motion accessibility setting.

## Shadow Presets (View extensions)

| Modifier | Shadow | Use |
|----------|--------|-----|
| `cardElevation()` | 0.08, r:3, y:1 | Default card state |
| `cardHoverElevation()` | 0.12, r:5, y:2 | Card hover state |
| `popoverElevation()` | 0.15, r:8, y:4 | Popovers, dropdowns |
| `toastElevation()` | 0.10, r:4, y:2 | Toast notifications, undo bars |

## Accessibility
- Liquid Glass auto-adapts: Reduce Transparency, Increase Contrast, Reduce Motion
- Keyboard navigation on all interactive elements
- VoiceOver labels on all controls (icon-only buttons use `.labelStyle(.iconOnly)`)
- `.accessibilityAddTraits(.isButton)` on tap gesture areas

## List Styles

| Style | Use |
|-------|-----|
| `.inset` | Data tables (Files, Sources) |
| `.sidebar` | Sidebar lists |
| `.inset` | Domain lists, activity feed |

## Sidebar Sections
- `.headerProminence(.increased)` on all section headers
- Item counts in `Typ.numericCaption` with `.foregroundStyle(.secondary)`
- Self-describing segmented controls (no external labels)

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-31 | Abandoned custom fonts (Satoshi/Geist) | Fights the platform. SF Pro IS the font. |
| 2026-03-31 | Liquid Glass as primary design language | macOS 26 native, curated, inevitable |
| 2026-03-31 | System semantic colours only | Auto light/dark, auto accessibility |
| 2026-03-31 | "Of course" test for all design choices | If it needs explanation, it's wrong |
| 2026-04-06 | Command palette (⌘K) for keyboard-first control | Raycast-inspired, all primary actions accessible |
| 2026-04-06 | Corner radii tokenized (6/10/12pt) | Prevents ad-hoc values, consistent surface language |
| 2026-04-06 | SwiftUI Table for file browsing | Finder-like columns, native sort, keyboard nav |
| 2026-04-06 | `.glassEffect()` only on chrome | Navigation-layer glass per WWDC25 core principle |
| 2026-04-11 | 3-tab model (Overview/Files/Emails) | Replaced 5-sidebar-item model. Per-tab sidebars. |
| 2026-04-11 | Persistent toolbar status indicator | Green/orange/red dot + text, visible on every tab |
| 2026-04-11 | No custom toolbar backgrounds | WWDC25 Session 356: Let Liquid Glass handle it |
| 2026-04-11 | Agent identity via dot + tint, no borders | Apple lets content carry identity, not decoration |
| 2026-04-11 | System semantic colors replace custom palette | .blue/.purple/.green/.orange/.red, no asset catalog |
| 2026-04-11 | Domain category sidebar with counts | Mail.app smart mailbox pattern for domain filtering |
| 2026-04-11 | FilesView converted to SwiftUI Table | Sortable columns, native keyboard nav, click-to-sort |
| 2026-04-11 | Typography weight by email volume | 100+ = body, 10-99 = callout, <10 = caption |
| 2026-04-26 | Brand mark `{ \| }` is structural, not decorative | The bar between braces IS the product. Mark = product thesis as glyph. |
| 2026-04-26 | Title sequence: SwiftUI iter-05 in-app, Canvas iter-06 web hero | Same identity, two render budgets. Both ship. |
| 2026-04-26 | Brand colors are NOT UI colors | Brand uses specific hex (warm ink + #B86A1E halo); UI stays system semantic only. Regression if brand hex appears in SwiftUI UI. |
| 2026-04-26 | Title-sequence morph slots match real Manifold scopes | `{ /files }` `{ /emails }` `{ /history }` — animation demonstrates the product, not decorates around it. |
