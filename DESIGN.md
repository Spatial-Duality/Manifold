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
- **Studio wordmark only:** IBM Plex Serif Semibold (sidebar header, About screen)
- **No custom fonts in the product.** SF Pro is the typeface.

## Colour
- **Approach:** System semantic tokens only
- **All functional colours:** `NSColor.controlAccentColor`, `.systemBlue`, `.labelColor`, `.secondaryLabelColor`, `.tertiaryLabelColor`
- **Brand accent (when resolved):** Single tint colour via `tintColor` on primary glass elements. Warm direction (hue 15-35 degrees). This becomes the app's accent colour in System Settings.
- **Agent colours:** Cowork = `.systemBlue`, Codex = `.systemPurple`
- **Warnings:** `.systemYellow` for sensitive file badges
- **Error/Restore:** `.systemRed` for critical restore actions
- **Success:** `.systemGreen` for sync badges, diff additions
- **No custom hex palette for UI.** System tokens adapt automatically.

## Liquid Glass

### Core Principle
Glass is the navigation layer. Content never uses glass. Do not stack glass on glass.

### SwiftUI API Reference (macOS 26+)

**Glass variants:**
- `Glass.regular` — default translucent glass. Use for most navigation chrome.
- `Glass.clear` — higher transparency. Requires media-rich background.
- `.tint(_ color:)` — adds color tint. Reserve for primary actions only.
- `.interactive()` — iOS only. Do NOT use on macOS.

**Primary modifier:**
```swift
.glassEffect(.regular, in: .capsule)       // Capsule shape (default)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
.glassEffect(.regular.tint(.blue))          // Tinted primary action
.glassEffect(.regular, isEnabled: condition) // Conditional
```

**Grouping (required when multiple glass elements coexist):**
```swift
GlassEffectContainer(spacing: 16) {
    HStack(spacing: 16) {
        Button("Edit") { }.glassEffect()
        Button("Share") { }.glassEffect()
    }
}
```

**Morphing transitions:**
```swift
@Namespace private var glassNS
Button("Action") { }
    .glassEffect(.regular)
    .glassEffectID("action", in: glassNS)
```

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
| Toolbar | Automatic glass (system toolbar) |
| Command palette | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Spacing.cornerLarge))` |
| Error banner | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Spacing.standard))` |
| Start Session CTA | `.buttonStyle(.glassProminent)` with `.tint(.accentColor)` |
| Session Preview Card | Non-glass card. Decision-payload-first hierarchy: totals header, per-source rows, email sensitivity context, size warnings |
| Session Preview Confirm | `.buttonStyle(.glassProminent)` with `.tint(.accentColor)` |
| Session Preview Cancel | `.buttonStyle(.glass)` |
| End Session | `.buttonStyle(.glass)` |
| Review Changes | `.buttonStyle(.glassProminent)` |
| Session recap dismiss | `.buttonStyle(.glass)` |
| Menu bar dropdown | Automatic glass (NSMenu) |
| Onboarding modal | System sheet (glass chrome, content non-glass) |

### Button Tint Hierarchy
- `.glassProminent` + `.tint(.accentColor)` — Start Session (strongest)
- `.glassProminent` — Review Changes
- `.glass` — End Session, secondary actions
- `.bordered` — tertiary actions, settings

### Fallback (pre-macOS 26)
```swift
if #available(macOS 26, *) {
    content.glassEffect(.regular, in: shape)
} else {
    content.background(.ultraThinMaterial, in: shape)
}
```

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

Respect safe area insets and corner adaptation regions.

## Layout
- NavigationSplitView with floating glass sidebar (`.navigationSplitViewStyle(.balanced)`)
- Single `.inspector()` on NavigationSplitView (full-height, Apple HIG)
- Sidebar column width: `min: 200, ideal: 220, max: 300`
- Content extends under sidebar (edge-to-edge)
- Sidebar: Home, Files, Emails, History, Sources (5 destinations)
  - Home: launchpad with session status, inline stats, recent activity
  - Files: SwiftUI Table with sortable columns (Finder-like file browser)
  - Emails: email management and selection for sharing
  - History: session-first timeline with inline event expansion
  - Sources: folder management with toggle and bulk context menus
- Settings is a separate scene (⌘,), 5-tab TabView
- Command palette (⌘K) for keyboard-first control

## Data Tables
- Use SwiftUI `Table` for data-dense file listings (Files tab)
- Sortable columns via `KeyPathComparator` bindings
- Columns: Name (with type icon), Source, Size, Modified, Versions, Kind
- Selection drives the app-level inspector via `store.inspectedFilePath`
- Right-click context menu with Finder-like actions (Reveal, Rename, Copy Path)

## Context Menus
- Files: Quick Look, Reveal in Finder, View History, Rename, Copy Path/Name, Open with Default App
- Sources: Pause/Resume, Reveal in Finder, Remove (single). Bulk: Pause/Activate N, Remove N.
- Both follow the `.contextMenu(forSelectionType:)` API pattern for multi-select support

## Corner Radii
| Token | Value | Use |
|-------|-------|-----|
| `small` | 6pt | Inline pills, command row hover |
| `medium` | 10pt | Cards, stat containers |
| `large` | 12pt | Section cards, session cards, command palette |

## Icons
- SF Symbols throughout
- No custom icon assets for UI controls
- Custom assets only: app icon, studio wordmark

## Motion
- System animations only. No custom spring/bounce.
- Scroll edge adaptive behavior (content dissolves under glass)

## Accessibility
- Liquid Glass auto-adapts: Reduce Transparency, Increase Contrast, Reduce Motion
- Keyboard navigation on all interactive elements
- VoiceOver labels on all controls
- 44px minimum touch targets

## Typography Weights

Three weights only. No bold. No light.

| Weight | Use |
|--------|-----|
| Regular (default) | Body text, descriptions, secondary content |
| Medium (`.weight(.medium)`) | Labels, section headers, source names, email senders |
| Semibold (`.weight(.semibold)`) | Screen titles in onboarding/welcome only |

## List Styles

| Style | Use |
|-------|-----|
| `.inset(alternatesRowBackgrounds: true)` | Data-dense lists: Files, Activity flat mode |
| `.inset(alternatesRowBackgrounds: false)` | Card-style lists: Sources, session grouped, Emails |

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-31 | Abandoned custom fonts (Satoshi/Geist) | Fights the platform. SF Pro IS the font. |
| 2026-03-31 | Liquid Glass as primary design language | macOS 26 native, curated, inevitable |
| 2026-03-31 | System semantic colours only | Auto light/dark, auto accessibility |
| 2026-03-31 | "Of course" test for all design choices | If it needs explanation, it's wrong |
| 2026-04-06 | 5 sidebar items: Home, Files, Emails, History, Sources | Direct naming, no metaphors. Files = file browser, Sources = folder management |
| 2026-04-06 | Command palette (⌘K) for keyboard-first control | Raycast-inspired, all primary actions accessible without sidebar |
| 2026-04-06 | Corner radii tokenized (6/10/12pt) | Prevents ad-hoc values, consistent surface language |
| 2026-04-06 | Stats as inline text, not card grid | Avoids AI slop 3-column pattern, calmer hierarchy |
| 2026-04-06 | Presets as Menu dropdown, not card grid | Avoids template-chooser AI slop, compact |
| 2026-04-06 | Session recap card after end session | Users see what happened before starting next session |
| 2026-04-06 | SwiftUI Table for file browsing, no nested split views | Finder-like columns, single inspector at app level per Apple HIG |
| 2026-04-06 | `.glassEffect()` on command palette, error banner, session cards | Navigation-layer glass per DESIGN.md core principle |
| 2026-04-06 | `.glassProminent` / `.glass` button styles with fallback helpers | Primary/secondary CTA hierarchy via glass tint prominence |
| 2026-04-06 | `glassBackground()` / `glassProminentButton()` / `glassButton()` helpers | Centralized `#available(macOS 26, *)` with `.ultraThinMaterial` / `.bordered` fallback |
| 2026-04-08 | Pre-session preview card: decision-payload-first hierarchy | Users see totals first ("Grant AI access to N sources"), details second. Not data-list-first. |
| 2026-04-08 | 5 preview interaction states (computing, error, no-sources, preview, cancel) | Every state visible, no silent failures. Computing shows ProgressView, error shows retry. |
| 2026-04-08 | Email sensitivity context in preview: "N of M emails visible (Strict filtering)" | Users understand what "Legal Review" means before confirming. Transparency over simplicity. |
| 2026-04-08 | Domain presets: strict/moderate/open email sensitivity | strict = shared only, moderate = hides banking/health/2FA, open = hides 2FA only. Stored on grant. |
