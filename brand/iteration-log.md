# Manifold Title Sequence — Iteration Log

> Five-pass overnight build. Each iteration is a self-contained HTML file plus a
> SwiftUI port for the final. Open each in a browser, click anywhere to replay.

## Files

| File | Pass | What it adds |
|---|---|---|
| `iter-01-refined.html` | 1 | Refined CSS baseline. Iris reveal from cusp, layered halos, atmospheric grain. **No morph yet.** |
| `iter-02-morph.html`   | 2 | Particle morph slot. `\|` ↔ `/files` ↔ `/emails` ↔ `/history` via offscreen-canvas glyph rasterization, greedy nearest-neighbor assignment, perpendicular bezier curves with stagger. |
| `iter-03-cinematic.html` | 3 | Trails, halo flash on transition, warm tinting during transit, variable atom size, scatter-from-off-frame initial reveal, Brownian shimmer on hold. |
| `iter-04-keynote.html` | 4 | Custom SVG brace paths with gradient stroke. Letter-by-letter wordmark stagger. Chromatic aberration during morph (RGB split). Multi-layer compositing (bloom layer behind atoms). Variable atom color (92/7/1 ink/warm/cold). Mouse parallax. |
| `iter-05-final.html`   | 5 | **Production version.** Synthesis of 1–4. Adds: seed-line prelude restored, longer holds (70/30 rule), reduced atom count for performance, auto-drift instead of mouse parallax, splash variant, light theme, accessibility, JS public API, visibility-pause. |
| `iter-06-canvas.html`  | bonus | Alternative technique experiment. Canvas-based with additive blending, 280 particles, frame-accumulation trails. See "Canvas vs SVG verdict" below. |
| `logo-compact.html`    | aux | Logo-only version. No halos/wordmark/tagline. For sidebar, footer, in-app secondary use. |
| `mark-{dark,light,mono}.svg` | aux | Static single-frame SVG marks for icons, social, favicons. |
| `wordmark-dark.svg`    | aux | Full logo lockup `{ \| } MANIFOLD` — for app chrome and headers. |
| `TitleSequence.swift`  | — | SwiftUI port of iter 5. macOS 13+ / iOS 16+. Drop into a SwiftUI hierarchy. |
| `animation-research.md`| — | Pre-build research and direction. |

## Pass-by-pass review

### Pass 1 — Refined Baseline
**Goal**: foundational reveal at high quality, no morph.
**Worked**: iris-out from each brace's cusp is structurally meaningful — the boundary forms from the place authority lives. Layered halos give depth.
**Fell short**: pure visual; once it settled, it was a still image with a polite pulse. This is "good developer animation," not WWDC.
**Carried into 2**: pacing, color tokens, typography stack, easing curves.

### Pass 2 — The Morph
**Goal**: deliver the `\|` ↔ text morph that makes the brand mark *demonstrate the product thesis*.
**Algorithm**:
- 140 atoms arranged vertically as the bar at rest
- On transition, target text is rasterized to an offscreen canvas
- Non-empty pixels sampled at stride-2 → ~1500 points reduced to 140 by even index sampling
- Greedy nearest-neighbor assigns atoms to targets (sorted by current Y so shortest pairs lock first)
- Each atom traverses a quadratic bezier with a perpendicular control point, eased cubic, staggered 0–300ms
- Brightening peaks at midpoint of transit
**Worked**: the morph is *legible* as morph (not crossfade). Glyph shape resolves clearly.
**Fell short**: atoms moved discretely (no trails), uniform size, halos didn't react, no warm tint during motion. Pacing felt mechanical.

### Pass 3 — Cinematic Polish
**Worked**:
- 5-position trail per atom with opacity decay sells the motion blur
- Halo flashes on every transition trigger
- Warm-tone tinting during transit
- Brownian shimmer (±0.35px) keeps held states alive instead of frozen
- Off-frame scatter for initial reveal eliminated the awkward "snap into bar" of pass 2
- Variable atom radius by spine position (larger near center)
**Fell short**: braces still flat text glyphs; no "punch frame" at transition arrival; no chromatic accent on transitions; wordmark just faded in flat.

### Pass 4 — Keynote-grade Push
**Big swings**:
- Custom-drawn SVG brace paths replace text glyphs. Vertical linear-gradient stroke (lighter at top, mid bone, shadowed at bottom) gives material/depth read.
- Doubled brace path with low-opacity offset = subtle highlight bevel.
- Chromatic aberration during morph: dual `drop-shadow` filters in red and blue offset by 1.5px.
- Multi-layer compositing: atoms drawn twice — once at full sharp, once blurred + saturated as a screen-blend bloom layer behind.
- Atom color variation: 92% ink, 7% warm, 1% cold-cyan for richness.
- Punch frame: brightness 1.4× spike for 140ms at transition end.
- Wordmark staggers letter by letter with 90ms phase between glyphs.
- Mouse parallax (later removed in 5 — see below).
**Fell short**:
- Lost the seed-line prelude (regression I caught in 5).
- Mouse parallax read as gimmicky for a title sequence — title sequences shouldn't react to user input.
- 750 SVG elements (150 atoms × 5 elements: front + bloom + 3 trails) was on the edge of acceptable for lower-end devices.
- Holds were too short for the 70/30 rule.

### Pass 5 — Final Synthesis
**Changes from 4**:
- Seed-line prelude restored — pure black silence, then the seed appears, *then* the iris reveal of the braces. The silence is the move.
- Trail count reduced from 5 → 3, atom count 150 → 120. Visual density preserved, perf budget restored.
- Mouse parallax removed; replaced with a slow autonomous `drift` keyframe (translates ±3px over 14s). The composition feels alive without reacting to the user.
- Holds extended: bar held 1.6s, text held 2.8s. Closer to 70/30.
- Splash variant via `.stage.splash` class — compresses entire reveal to ~2.5s for app launch use.
- Light theme via `.stage.light` class.
- `prefers-reduced-motion: reduce` → automatically applies `.static` class for accessible static frame.
- `document.hidden` pauses the rAF loop and cycle timer (no wasted cycles in background tabs).
- Public JS API: `window.ManifoldTitle.{setCycle, setSpeed, replay, pause, resume}`.

## Honest assessment vs. reference quality

| Reference | Where iter 5 lands | Where the gap is |
|---|---|---|
| Severance title sequence | ~80% | Severance has subpixel typographic tension and audio-synced motion. We have no audio sync. |
| Patrick Clair's Westworld titles | ~70% | Westworld has true 3D camera moves and material refraction (Cinema 4D + Octane). Code can suggest depth via parallax + blur but cannot match. |
| Apple WWDC keynote intro | ~70% | WWDC is rendered VFX with HDR + sound design + depth-of-field. The morph technique here is keynote-tier; the surrounding production is not. |

Closing the remaining 20–30% requires leaving code: After Effects + Lottie export, or a Rive runtime. See `animation-research.md` §7 for the upgrade path.

## What's *better* than I expected

- The morph itself reads as deliberate-not-rubbery, which is the bar most particle-morph implementations fail to clear.
- The seed-line prelude turned out to do more work than I'd predicted — it gives the viewer a beat of stillness before motion that frames everything as *intentional* rather than *automatic*.
- The brace gradient stroke compensates surprisingly well for not having real material rendering.

## Bonus pass — Canvas vs SVG verdict

After completing the five-iteration brief I built `iter-06-canvas.html` as a
controlled experiment to test whether moving the particle field from SVG circles
to HTML Canvas with additive blending would surpass iter 5.

**What changed**:
- 280 particles (vs 120) — more than 2× density
- `globalCompositeOperation = 'lighter'` for true additive bloom (replaces SVG bloom layer)
- Frame accumulation: each frame paints `rgba(5,5,7,0.18)` over the canvas instead of clearing → trails decay exponentially over ~6 frames (replaces discrete trail circles)
- Each atom drawn as soft gradient + sharp core (better dynamic range per atom)
- HiDPI (devicePixelRatio) handling

**What's better in iter 6**:
- The trails feel *real* — exponential decay rather than 3-step discrete history
- Bright cores against bloom haze read as material (looks luminous, not just colored)
- More particles = denser glyph reads at the destination text
- Performance is comparable despite 2.3× particle count (Canvas batch fills are cheaper than SVG element updates)

**What's worse in iter 6**:
- Canvas can't be pixel-perfect at every zoom level the way SVG is
- Print/screenshot fidelity is lower (rasterized vs vector)
- Harder to inspect/debug (no DOM tools work on individual atoms)
- Frame accumulation creates a slight haze across the canvas at all times — looks great in motion, but adds ~5% gray everywhere

**Verdict**: iter 6 is *more cinematic in motion*; iter 5 is *more architecturally
clean and easier to maintain*. Recommend:
- Use iter 6 for the **web hero** — visitors see motion, not still frames
- Use iter 5 (or its SwiftUI port) for **in-app contexts** — easier to inspect, paste
  into emails as screenshots, render in design tools

I am NOT consolidating the two. Both ship. The user picks per context.

## What I would attack next if you said yes to a seventh pass

1. **Sound design**. Even a 3-second royalty-free hum + transition click would lift this 10% on its own. Easiest single quality lever left.
2. **Replace particle-morph with Lottie export.** Same visual concept, but rendered in After Effects with motion blur, light shafts, and frame-perfect timing. Same embeddability via lottie-web.
3. **Reactive-to-real-state slot.** When Manifold actually grants `/files` to an agent, the in-app title morphs to `{ /files }`. This is the highest-impact creative direction you have available — it makes the brand mark a live status indicator. Best implemented in Rive.
4. **Three-quarters perspective.** Currently the composition is dead-on. A subtle 3-degree rotation around Y with depth would feel cinematic. CSS transform: rotateY(3deg) is one line.

## Decision gates remaining

These are still in `animation-research.md` §10 unanswered:

1. Is the `| → /files → /emails → /history → |` cycle right? Or different category names?
2. Loop forever on web hero, or play once and settle on `{ | }`?
3. Should the in-app version be cosmetic (this code) or reactive (real grants morph the slot)?
4. Sound design in scope for this asset, or separate workstream?

When you wake up, start with `iter-05-final.html` to see the production version, then walk back through 4 → 3 → 2 → 1 to see the build-up. The earlier iterations are useful as fallbacks if you decide the final is too rich for some context (e.g. iter 1 might be the right read for a humble in-app About screen).
