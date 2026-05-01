# Manifold App Icon Design Guide

A research-backed, step-by-step method for designing Manifold's macOS app icon under the Liquid Glass system introduced at WWDC 2025.

---

## Part 1: What You're Actually Designing

### The New Icon System (macOS 26 / Liquid Glass)

App icons are no longer flat PNGs. They're multi-layered compositions rendered through Apple's Liquid Glass material system. The glass itself adds depth, edge highlights, frostiness, translucency, and dynamic lighting — so your artwork needs to be simpler than you think.

**Key facts:**
- Canvas: 1024×1024px (all platforms except watchOS which is 1088px)
- Layers: minimum 2 (background + 1 foreground), maximum 4 groups
- File format: `.icon` (created in Icon Composer, replaces asset catalogs)
- Appearance modes: Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark
- The platform mask (rounded rectangle on macOS) is applied automatically — do NOT include it in your artwork
- No drop shadows, no baked-in bevels — the material system provides these dynamically

### What Apple Changed from the Old System

Previously: you designed a flat icon at 1024×1024, exported at multiple sizes, and dropped PNGs into an asset catalog.

Now: you design separate layers (SVG or PNG), import them into Icon Composer, configure materials and glass effects, and export a single `.icon` file that Xcode handles across all platforms and all appearance modes.

The fundamental shift: **the material does the heavy lifting.** Your job is to provide clear, simple shapes with good separation between layers. The glass, lighting, highlights, and shadows are handled by the system.

---

## Part 2: Design Principles from WWDC 2025

These come from two WWDC25 sessions — "Say hello to the new look of app icons" (Session 220) and "Create icons with Icon Composer" (Session 361).

### 1. Simplicity Over Illustration

**Do:** Frontal views, flat shapes, reduced detail. Let the material add nuance.
**Don't:** Realistic 3D objects, complex illustrations, heavy texturing.

The old Chess icon had a detailed 3D perspective rendering. The new one is a flat frontal view. The glass material makes it look dimensional without the artwork needing to be.

### 2. Layer Separation Creates Depth

**Do:** Separate foreground elements from background by color and by depth. Each distinct visual element should be its own layer.
**Don't:** Flatten everything into one image. That defeats the entire system.

Messages icon: one foreground layer (the speech bubble) on a background. Simple. The material adds all the depth through translucency and shadow.

Podcasts icon: multiple stacked foreground layers creating true dimensional separation. Each ring is its own layer.

### 3. Rounded Edges, Bold Lines

**Do:** Round corners on all shapes. Use bold line weights. Light travels along rounded edges beautifully in Liquid Glass.
**Don't:** Sharp corners, thin lines, hairline details. These break the light flow and disappear at small sizes.

Settings gear icon: old version had sharp teeth. New version has rounded teeth. The difference in how light travels is dramatic.

### 4. Background Gradients, Not Flat Color

**Do:** Use soft gradients (light-to-dark) that harmonize with the lighting direction. Apple provides System Light and System Dark gradient presets.
**Don't:** Pure white or pure black backgrounds. These kill the glass effect.

### 5. Avoid Baked-In Effects

**Do:** Let Icon Composer handle shadows, highlights, specular reflections.
**Don't:** Add drop shadows, inner shadows, embossing, or glows in your artwork. These fight with the dynamic material and look wrong when the appearance mode changes.

### 6. Reduce Overlap

**Do:** Give elements breathing room. Let glass intersections and reflective edges be visible.
**Don't:** Stack many overlapping translucent elements — they muddy each other and obscure the material's beauty.

### The Gruber Warning

John Gruber's critique of macOS 26 utility icons is instructive: Apple's own "wrench and bolt" utility icons fail because only ~10% of the icon area shows what the app actually does. The rest is a generic wrench. The lesson: **every pixel of your icon should serve identification.** Don't waste space on a generic frame or motif.

---

## Part 3: Manifold-Specific Concept Work

### What the Icon Must Communicate

Manifold is "the user-owned observation and reversibility layer for AI agent work." The icon needs to evoke:

**Primary:** Observation / visibility / seeing what happened
**Secondary:** Protection / safety / your files are safe
**Tertiary:** Versioning / layers / history

**What it must NOT evoke:**
- Paranoia or surveillance (this isn't a security scanner)
- Complexity or enterprise software
- AI or robots (this is a user tool, not an AI product)

### Visual Metaphors to Explore

Think about what physical objects carry the right emotional weight:

| Metaphor | Pros | Cons |
|----------|------|------|
| **Prism / crystal** | Refracts light (observation), layers visible inside, works beautifully with Liquid Glass translucency | Abstract, might not read at 16px |
| **Magnifying glass over layers** | Direct "see what happened" metaphor, layers = versioning | Preview already uses a loupe; too close |
| **Folded/layered pages** | Version history, stacking, files | Generic, looks like a document manager |
| **Eye / iris** | Observation, clarity, watching | Surveillance connotation, privacy tool irony |
| **Shield with layers** | Protection + versioning | Too "security product," contradicts calm positioning |
| **Window / portal** | Look through to see what's underneath, clarity | Could look like a browser or screen sharing app |
| **Manifold (the mathematical object)** | Name reference, surfaces folding through each other, transformation | Too abstract for most people, won't read at 16px |
| **Layered glass panes** | Literally what Liquid Glass does best, depth, transparency, files behind glass | Might be too literal / too similar to other glass icons |

### Recommended Direction

Given Manifold's positioning (calm, native, trustworthy — "Pixelmator Pro is the target bar") and the Liquid Glass system's strengths, the strongest direction is likely:

**Abstract geometric form with visible internal layers.** Something like overlapping translucent planes or a prism-like shape where you can see through to layers beneath. This:
- Exploits Liquid Glass translucency (the system will make this look stunning)
- Communicates "layers / versions / depth" without text
- Reads at 16px as a distinctive silhouette
- Doesn't evoke surveillance, security, or enterprise
- Is unique — no major macOS app uses this visual language

**Color direction:** Blue is the natural choice (it's already your primary UI color for Claude, and blue = trust in UI design psychology). But consider: your agent colors are blue (Claude) and purple (Codex). The icon could use a gradient between these — or it could deliberately be neutral (using Apple's System Light/Dark gradients) to signal "this is the independent layer, not tied to any agent."

### The 16px Test

Before finalizing any concept, shrink it to 16×16 pixels (Dock minimum size, menu bar size). If you can't identify it at that size, the design has too much detail. The best macOS icons have a distinctive silhouette that works at any size: Finder's face, Safari's compass, Messages' speech bubble.

---

## Part 4: The Production Method (Step by Step)

### Phase 1: Concept (1-2 hours)

**Tools needed:** Paper + pencil, or iPad + Procreate/Freeform

1. Sketch 10-15 rough concepts at ~50×50mm on paper. Don't self-edit. Explore all the metaphors above plus anything else that comes to mind.
2. Circle the 3-4 that have the strongest silhouette.
3. For each finalist, redraw at two sizes — 50mm (detail view) and 10mm (dock test). If it's unrecognizable at 10mm, cut it.
4. Pick one direction. Commit.

### Phase 2: Vector Design (2-4 hours)

**Tool:** Figma (free) or Sketch or Affinity Designer

1. **Download Apple's icon template** from [Apple Design Resources](https://developer.apple.com/design/resources/). They provide Figma, Sketch, Photoshop, and Illustrator templates with the correct grid and safe zones.

2. **Work at 1024×1024** on the template grid.

3. **Design in layers from the start.** This is critical. Don't design a flat icon and then try to decompose it. Think in layers from the first vector stroke:
   - **Layer 1 (Background):** Your base color/gradient. Use a soft gradient, not flat color. Consider Apple's System Light gradient as a starting point.
   - **Layer 2 (Primary shape):** The main recognizable form. This carries 80% of the identification.
   - **Layer 3 (Detail/accent):** If needed. A secondary element that adds meaning. Keep it simple.
   - **Layer 4 (Top highlight, optional):** Only if your concept genuinely needs 4 depth levels. Most icons are better with 2-3.

4. **Design rules for each layer:**
   - Foreground layers MUST have transparent backgrounds
   - Convert all text to outlines (fonts aren't preserved in SVG)
   - Round all corners — no sharp angles
   - Bold stroke weights (test at 16px — if a line disappears, it's too thin)
   - No shadows, no glows, no embossing, no gradients that simulate 3D lighting
   - Separate different colors into different layers (gives more control in Icon Composer)

5. **Check appearance modes mentally:**
   - Will this read on a dark background? (Dark mode)
   - Will this read as a single-tone silhouette? (Tinted mode)
   - Will this read with the wallpaper visible through it? (Clear mode)
   - If any mode fails, simplify.

6. **Export each layer:**
   - SVG for vector shapes (scalable, preferred)
   - PNG at 1024×1024 for any rasterized elements (blur, texture)
   - Foreground layers: transparent background
   - Background layer: opaque, full canvas

### Phase 3: Icon Composer Assembly (1-2 hours)

**Tool:** Icon Composer (bundled with Xcode 26, also standalone download from [Apple Developer](https://developer.apple.com/icon-composer/))

1. **Open Icon Composer.** Start a new icon.

2. **Import background layer first.** This becomes the base of your glass stack.

3. **Import foreground layers in order** (back to front). Each layer becomes a depth group. You can have up to 4 groups.

4. **Configure per-layer materials:**
   - **Liquid Glass toggle:** Enable for layers that should have the glass effect
   - **Fill:** Base color/gradient
   - **Opacity:** Adjust translucency
   - **Blend mode:** Experiment, but normal is usually right
   - **Specular highlights:** How light catches edges (let the defaults do their thing first)
   - **Shadows:** Choose neutral or chromatic (chromatic = color-aware shadow casting, more sophisticated)

5. **Preview across all appearance modes:**
   - Default (Light)
   - Dark
   - Clear Light
   - Clear Dark
   - Tinted Light
   - Tinted Dark
   - If any mode looks wrong, go back to Figma and adjust the problematic layer

6. **Preview across platforms:** iPhone, iPad, Mac, Watch. Even if you're only shipping on Mac, the icon should work everywhere in case you expand later.

7. **The "squint test":** Zoom the preview to the smallest size. Squint. Can you still identify it? If not, simplify.

8. **Export:**
   - Save as `.icon` file (this is your master — add to version control)
   - Export flattened PNG for marketing/website use (Icon Composer has an export option for this)

### Phase 4: Xcode Integration (15 minutes)

1. Drag the `.icon` file into Xcode's project navigator (into the `ManifoldApp` group)
2. Open the target's General tab
3. Set the "App Icon" field to match the `.icon` filename (without extension)
4. Build and run — verify the icon shows in the Dock and Finder

**Note for Manifold specifically:** The existing `Assets.xcassets` has no AppIcon set. You're adding one from scratch, so there's nothing to replace.

### Phase 5: Menu Bar Icon (Separate Asset)

The menu bar icon is NOT the same as the app icon. It's a template image:

- **Size:** 18×18pt (36×36px @2x, 54×54px @3x)
- **Color:** Single color (the system tints it for light/dark menu bar)
- **Style:** Simplified version of the app icon's primary shape, or a distinct glyph
- **Format:** PDF (preferred for template images) or @1x/@2x/@3x PNGs
- **Design:** Must work as a solid silhouette. No gradients, no detail, no glass effects.

Your `manifold_menubar_plan.svg` wireframe shows 3 states (Idle, Active, Attention). Design the base glyph, then create variants with small state indicators (e.g., a dot or pulse for active, an exclamation for attention).

Consider using an SF Symbol as the base if one is close enough — they automatically adapt to menu bar weight and size.

---

## Part 5: Quality Checklist

Before shipping the icon, verify:

- [ ] Reads as a distinctive silhouette at 16×16px
- [ ] Works in all 6 appearance modes (Default, Dark, Clear Light/Dark, Tinted Light/Dark)
- [ ] No baked-in shadows, glows, or embossing in the artwork layers
- [ ] All corners are rounded (no sharp angles)
- [ ] Line weights are bold enough to survive at small sizes
- [ ] Background uses a gradient, not flat white or flat black
- [ ] Foreground layers have transparent backgrounds
- [ ] All text has been converted to outlines
- [ ] The `.icon` file builds correctly in Xcode with no warnings
- [ ] The icon doesn't look like an existing macOS app (Safari compass, Preview loupe, etc.)
- [ ] The menu bar icon works as a single-color template image at 18pt
- [ ] The icon evokes "calm observation" not "surveillance" or "security paranoia"
- [ ] The icon is consistent with Manifold's design position: deeply native, not custom-skinned
- [ ] You've shown it to 3-5 people and they can guess the app's general category (file management / developer tool) without being told

---

## Part 6: Reference Material

### WWDC 2025 Sessions (Watch These)
- **Session 220:** "Say hello to the new look of app icons" — design principles, examples, do's and don'ts
- **Session 361:** "Create icons with Icon Composer" — the tool walkthrough
- **Session 219:** "Meet Liquid Glass" — how the material system works
- **Session 356:** "Get to know the new design system" — broader context

### Tools
- **Design:** Figma (free), Sketch, Affinity Designer, Photoshop, Illustrator
- **Assembly:** [Icon Composer](https://developer.apple.com/icon-composer/) (free, from Apple)
- **Templates:** [Apple Design Resources](https://developer.apple.com/design/resources/) — official grid templates for Figma, Sketch, Photoshop, Illustrator
- **Integration:** Xcode 26

### Icon Galleries for Research
- [macOS Icon Gallery](https://www.macosicongallery.com/) — curated collection of macOS icons
- [macOSicons](https://macosicons.com/) — 30k+ community icons, useful for seeing what exists
- [BasicAppleGuy's macOS Icon History](https://basicappleguy.com/basicappleblog/macos-icon-history) — evolution of Apple's system icons through every macOS release

### Icons to Study (What "Calm + Native + Trustworthy" Looks Like)
- **Pixelmator Pro** — professional tool that feels calm and precise
- **Things 3** — utility that feels native and trustworthy, not enterprise
- **Fantastical** — distinctive but deeply macOS-native
- **Raycast** — developer tool with clean, recognizable identity
- **1Password** — trust/security positioning without paranoia
- **Transmit** — file management tool with clear visual identity

### What to Avoid
- Generic shield icons (screams "security product")
- Gear/wrench motifs (Apple's own utility icons are a cautionary tale — see Gruber's critique)
- Padlock icons (too literal, too aggressive)
- AI/robot imagery (this is a user tool, not an AI product)
- Overly complex illustrations that compete with the glass material
