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

### Surface Mapping
| Surface | Glass Treatment |
|---------|----------------|
| Sidebar | Floating sidebar with `automaticallyAdjustsSafeAreaInsets` |
| Toolbar | System toolbar with glass |
| Source badges | `NSItemBadge.count(n)` |
| Grant/End/Refresh | `button.bezelStyle = .glass` with tint prominence hierarchy |
| Menu bar dropdown | System `NSMenu` (automatic glass) |
| Onboarding modal | System sheet (glass chrome free, content non-glass) |
| CoworkGuardrail | System `NSAlert` |

### Button Tint Hierarchy
- `.primary` — "Grant to Claude" (strongest, default action)
- `.secondary` — "Refresh and Continue"
- `.none` — "End Access"

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
- NavigationSplitView with floating glass sidebar
- Content extends under sidebar (edge-to-edge)
- Sidebar: Sources, Profiles, Activity (3 items, not 4)
- Activity view IS the restore interface

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
