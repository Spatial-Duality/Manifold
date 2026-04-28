# Manifold Brand — Title Sequence

Self-contained title sequence for web hero, app splash, and in-product use.
Five iterations of motion design built overnight 2026-04-26.

## Quick start

**View all five iterations side-by-side:**
Open `index.html` in a browser. Use the buttons in the header (or keyboard 1-5) to switch.

**Embed the production version on a website:**
```html
<iframe src="iter-05-final.html"
        style="border:0; width:100%; height:100vh"></iframe>
```

Or copy the `<style>` and `<body>` contents from `iter-05-final.html` into a hero
section directly.

**Use in the Manifold app (SwiftUI):**
```swift
import SwiftUI

struct SplashView: View {
    var body: some View {
        ManifoldTitleSequence(speed: 2.5)        // splash speed
            .frame(width: 600, height: 400)
    }
}
```

`TitleSequence.swift` lives here for reference. To use it in the Manifold target,
move it to `ManifoldApp/ManifoldApp/Views/Brand/TitleSequence.swift` and add it to
the Xcode project.

## Files

| File | Purpose |
|---|---|
| `index.html` | Iteration comparison switcher with keyboard shortcuts |
| `iter-01-refined.html` | Pass 1 — refined CSS baseline, no morph |
| `iter-02-morph.html` | Pass 2 — particle morph slot first appears |
| `iter-03-cinematic.html` | Pass 3 — trails, warm transit tint, halo flash |
| `iter-04-keynote.html` | Pass 4 — custom braces, letter stagger, chromatic aberration |
| `iter-05-final.html` | **Production for in-app & embedded.** |
| `iter-06-canvas.html` | **Production for web hero.** Canvas + additive blending — more cinematic in motion. |
| `logo-compact.html` | Logo-only version (no halos/wordmark) for sidebar, footer, secondary contexts |
| `mark-dark.svg` / `mark-light.svg` / `mark-mono.svg` | Static single-frame marks |
| `wordmark-dark.svg` | Full logo lockup `{ \| } MANIFOLD` |
| `TitleSequence.swift` | SwiftUI port of iter 5 |
| `animation-research.md` | Pre-build research, references, technical decisions |
| `iteration-log.md` | Pass-by-pass review of what worked, what fell short |

## Configuration (web)

The production HTML exposes a global API:

```js
window.ManifoldTitle.setCycle(['bar','files','emails','history']);
window.ManifoldTitle.setSpeed(1.2);   // 0.3 - 3.0
window.ManifoldTitle.replay();
window.ManifoldTitle.pause();
window.ManifoldTitle.resume();
```

CSS class variants on `.stage`:

| Class | Effect |
|---|---|
| `.splash` | Compresses entire reveal to ~2.5s for app launch |
| `.light` | Light theme |
| `.static` | No animation (final frame only) |

`prefers-reduced-motion: reduce` automatically applies `.static`.

## Configuration (SwiftUI)

```swift
ManifoldTitleSequence(
    speed: 1.0,
    cycle: [.files, .bar, .emails, .bar, .history, .bar],
    wordmark: "MANIFOLD",
    tagline: "ACCESS, RECORDED."
)
```

Requires macOS 13+ / iOS 16+ (uses `Canvas` + `TimelineView`).

## Performance

Iter 5 targets:
- 60fps on M1 / Apple Silicon
- 120 atoms × 5 SVG elements (front + bloom + 3 trails) = 600 animated nodes
- Pauses on `document.hidden` (web) and inactive scene (SwiftUI)

If you see frame drops on lower-end devices, drop `ATOM_COUNT` in the JS constant
from 120 to 80, or reduce `TRAIL_LENGTH` from 3 to 2. Quality drop is minimal,
~30% perf gain.

## Quality ceiling

CSS + JS lands at roughly 80% of Apple TV+ title-sequence quality. The remaining
20% requires either a Lottie export from After Effects (motion blur, frame-perfect
timing) or a Rive runtime (state-machine driven, native iOS + web). See
`animation-research.md` §7 and `iteration-log.md` for upgrade-path detail.

## Decisions still pending

These are unanswered in `animation-research.md` §10:

1. Slot inventory: ship with `| → /files → /emails → /history → |`?
2. Web hero behavior: continuous loop, or play once and settle?
3. In-app version: cosmetic loop, or reactive (real grants morph the slot)?
4. Sound design: in scope, or separate workstream?
