# Manifold Title Sequence — Research & Direction

> Status: pre-implementation thinking. Decisions in this doc gate the build.
> Owner: Amar. Last updated: 2026-04-26.

## 1. The Brief, Restated

The vertical bar in `{ | }` is not a static gate. It is a **slot** that mutates to reveal what the boundary currently permits:

```
{ | }  →  { /files }  →  { | }  →  { /emails }  →  { | }  →  { /history }  →  { | }
```

The braces are the **permanent contract**. The slot is the **living grant**.
The animation is the product thesis in 8 seconds.

This requires real morphing, not crossfades. Crossfades are the fingerprint of amateur work; the eye reads them as "two things were swapped." Morphs read as "one thing transformed." That difference is exactly the gap between a stock template and a Patrick Clair title.

## 2. Reference Set

What we're stealing from, and what specifically.

### Primary: Severance (Apple TV+)
- **What we steal**: cold restraint, long holds (3-4s), typographic primacy, deliberate
  asymmetry, off-white on warm-black, precision over flourish.
- **What we don't steal**: surreal liquidity. Manifold is a trust product, not a horror
  product. Things should feel inevitable, not unsettling.

### Secondary: Patrick Clair's body of work
- *Westworld* S1, *True Detective* S1, *Halo* — schematic precision, multi-layered
  reveals where forms appear to *construct themselves* rather than fade in.
- Technique to borrow: progressive reveal where each element has visible *anticipation*
  before it commits.

### Tertiary: Apple's own Liquid Glass / visionOS motion language
- Material that has weight, refracts, settles. Subtle parallax on focal elements.
- We can approximate the *signal* of this with shadow + halo + slight scale-overshoot,
  without paying the WebGL cost.

### What to actively avoid
- *Foundation* — too cosmic/space-opera; wrong for a security tool.
- *Stranger Things* — playful imperfection; wrong tone for trust.
- Anything bouncy. No spring physics on the mark itself. Springs read as "fun app."
  Manifold is not a fun app — it's an indispensable one.

## 3. Three Technical Approaches (Honest Trade-offs)

### A. SVG Path Morphing — GSAP MorphSVG / Flubber.js
- **Pro**: vector-precise, deterministic, scales infinitely
- **Con**: morphs between topologically dissimilar shapes (`|` has 1 closed path,
  `/files` has 6+) look rubbery without heavy hand-tuning per pair
- **Verdict**: Useful as a *finishing layer* on individual letterforms.
  Cannot carry the main `|` ↔ `/files` transition alone.

### B. Particle Dissolution — Canvas or SVG circles
- **Pro**: handles topology change *naturally* (atoms find their new home),
  reads as material/atmospheric, this is how Apple does encryption visuals
- **Con**: more code, requires hand-tuning particle physics (stagger, easing,
  trail decay) to avoid looking like a screensaver
- **Verdict**: **This is the right primary technique.** It is the single largest
  quality lever we can pull without leaving code.

### C. Variable Font Animation
- **Pro**: pure CSS, native font rasterization, perfect at every scale
- **Con**: only morphs *within* a glyph (weight, width, slant). Cannot morph
  between unrelated glyphs.
- **Verdict**: Good for *sub-effects* — wordmark settling, the slot text
  "breathing" while held — but not the main morph.

### D. Lottie (After Effects export)
- **Pro**: 95%+ Apple-TV+ quality, motion blur is real, frame-perfect
- **Con**: requires AE proficiency, larger payload, JSON format opaque
- **Verdict**: This is the upgrade path if code-based output isn't enough.
  Defer until the code version is shipped and judged.

### E. Rive
- **Pro**: state-machine driven, runs natively in iOS *and* web,
  could be triggered by real Manifold app events ("a new policy was granted")
- **Con**: another runtime dependency, learning curve
- **Verdict**: Strongest candidate if this animation needs to be *reactive to
  product state* in the app (i.e., when a real grant happens, animate the slot).

## 4. Recommended Architecture: Particle Hybrid

```
┌──────────────────────────────────────────────────────────────┐
│  STABLE LAYER (CSS):                                          │
│    { ........... }       Braces — fixed, never animate       │
│                                                                │
│  MORPH LAYER (Canvas or SVG circle field):                    │
│    [....|....]           80–120 luminous atoms                │
│       ↓                  Repositioned each transition         │
│    [/files]              Targets sampled from glyph raster    │
│                                                                │
│  ATMOSPHERE LAYER (CSS):                                      │
│    halo, grain, vignette — never animates with the morph     │
└──────────────────────────────────────────────────────────────┘
```

### Morph algorithm
1. At rest, 80 atoms are arranged in a tight vertical line — visually they read as `|`.
2. On morph trigger, the system:
   - Rasterizes the target string (e.g. `/files`) into a binary mask
   - Samples ~120 points from that mask, weighted toward stroke centers
   - Assigns each atom a target — bar atoms get text targets via Hungarian-like
     nearest-neighbor; surplus targets are filled by atoms fading *in* from the halo;
     surplus atoms fade *out* into the halo
3. Each atom travels with:
   - Cubic-bezier easing `(0.65, 0, 0.35, 1)` — confident, no bounce
   - Stagger by index: 0–280ms phase offset
   - Slight perpendicular curve (atoms don't move in straight lines — straight
     lines are the second amateur tell after crossfades)
   - Trail with opacity decay (cheap motion blur)
4. At t=0.45 of the morph, a brief brightening pulse at midpoint — the "phase change"
5. After settle, the slot holds with a subtle variable-weight breathe (200ms cycle,
   ±0.05 weight delta, almost imperceptible)
6. Reverse to return to `|`

This is achievable in ~400 lines of vanilla JS + SVG. No paid dependencies.

## 5. Pacing Philosophy — The 70/30 Rule

Apple-TV-quality title sequences are **70% hold, 30% motion**. Amateur work inverts
this. The viewer needs time to *commit to reading* what's on screen before the next
change.

Proposed timeline (cinematic web hero, 12s loop):

```
0.0 – 1.5s    Initial reveal: braces grow, bar materializes, halo brightens
1.5 – 4.0s    Hold on { | }                              ← 2.5s commit
4.0 – 4.7s    Morph: | → /files                          ← 700ms
4.7 – 7.0s    Hold on { /files }                         ← 2.3s commit
7.0 – 7.7s    Morph: /files → /emails  (skip back to |)
7.7 – 10.0s   Hold on { /emails }
10.0 – 10.7s  Morph: /emails → /history
10.7 – 12.0s  Hold, then loop back to | seam-matched
```

Every transition is bracketed by a long hold. The held states are *the message*.
The morphs are *the proof of motion*.

For the **app splash**, compress to one cycle: `| → /files → |` over 2.5s.

## 6. Slot State Inventory (Decision Needed)

What strings cycle through the slot? Each state must be:
- ≤ 8 characters wide so the composition stays balanced
- Recognizable as a *category of access*, not a specific file
- Plausibly a real grant Manifold could make

Proposed:
```
{ | }            ← rest / locked state
{ /files }       ← filesystem grant
{ /emails }      ← mailbox grant
{ /history }     ← past activity / version log grant
{ /tasks }       ← (optional) active work
{ ! }            ← (optional) pending review state
{ ✓ }            ← (optional) protected/recorded confirmation
```

I'd ship with `| → /files → /emails → /history → |`. Adding `!` and `✓` is
tempting but risks turning the title sequence into a feature list.

## 7. Quality Ceiling — Honest Assessment

| Approach | Quality vs. Apple TV+ | Effort |
|---|---|---|
| Current `title-sequence.html` (CSS only) | ~70% | shipped |
| + Particle morph slot (this plan) | ~85% | 6 hours |
| + Lottie export from AE | ~95% | 2 days + AE skill |
| + WebGL fluid shader | ~98% | 1 week |

No real Apple TV+ show is rendered in WebGL on the web. The 85% target is the
right ambition. Past 90% you're paying disproportionate effort for diminishing
viewer impact.

## 8. What Code Cannot Do (and Where to Upgrade if Needed)

- **True material refraction** (Liquid Glass) → would need WebGL shaders.
  Not worth the cost for this asset.
- **Frame-perfect motion blur** → Canvas approximates with trail decay; AE/Lottie
  is perfect. Upgrade only if A/B testing shows the morph reads "digital."
- **Synced audio** → CSS/JS can trigger HTML5 audio elements but proper title
  sequences have *sound design* — soft hum on hold, click on transition,
  sub-bass on initial reveal. Out of scope here; flag as a separate workstream.
- **Real product reactivity** → if you want the slot to morph *in response to
  actual grants happening in the app*, that requires Rive or a custom Lottie
  bridge. Worth considering for the in-app version.

## 9. Implementation Roadmap

| Stage | Output | Effort |
|---|---|---|
| 0 | This doc, signed off | done |
| 1 | Refactor `title-sequence.html` to host morph slot | 1h |
| 2 | Particle system: `\|` ↔ rendered text glyph | 3h |
| 3 | Pacing, holds, easing tuning, accessibility, splash variant | 2h |
| 4 | SwiftUI port using `TimelineView` + `Canvas` | 2h |
| 5 | Lottie/Rive upgrade-path doc (no implementation) | 30m |

## 10. Decision Gates (For Amar Before I Build)

1. **Slot inventory**: ship with `| → /files → /emails → /history → |`?
   Or different strings?
2. **Loop behavior on web**: continuous loop, or play once and hold on `{ | }`?
3. **In-app behavior**: cosmetic loop, or reactive (slot reflects real grants)?
4. **Color**: keep current warm-bone-on-warm-black, or test a cold variant
   (steel/pale-blue) for a more Severance-y read?
5. **Sound design**: in scope for this pass, or separate workstream?

Once these are decided, I'll build stages 1-4. Stage 5 (Lottie/Rive doc)
should happen regardless so you have the upgrade path documented.
