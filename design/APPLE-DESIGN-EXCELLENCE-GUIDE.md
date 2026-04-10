# Manifold — Apple Design Excellence Guide

> **Purpose**: A practitioner's reference for elevating Manifold from "good macOS app" to "Apple Design Award contender." Every principle here is derived from WWDC sessions, Apple HIG, and analysis of award-winning apps like Pixelmator Pro. Code samples target Swift 6, SwiftUI, macOS 26.
>
> **How to use**: Read the principle, understand *why*, then apply the code pattern to the specific Manifold surface listed. This is not a theoretical document — it's a build checklist.

---

## Part 1: Liquid Glass — The macOS 26 Material System

### 1.1 Core Principles (WWDC25 Session 219 — "Meet Liquid Glass")

Liquid Glass is not a style you apply everywhere. It's a semantic layer that means "this is navigation chrome." The rules are strict:

**Glass goes on navigation layers only.** Toolbars, tab bars, sidebars, floating controls. Never on content. Never on data rows. Never on cards that display information. The moment glass appears on content, the user loses the ability to distinguish "where am I" from "what am I looking at."

**Never glass-on-glass.** If a toolbar already has glass, a button inside it does not get its own glass effect. The container provides the material; children inherit it. Doubling up creates visual mud — the lensing effects interfere with each other.

**Regular variant 95% of the time.** `.glassEffect(.regular)` is the default. `.glassEffect(.prominent)` is reserved for the single most important control on screen (e.g., a tab bar). If everything is prominent, nothing is.

**Materialize, don't fade.** When glass elements appear or disappear, they should morph in using `glassEffectID` — not fade with opacity. Glass fading looks broken because the lensing cuts abruptly. Morphing maintains the physical metaphor.

### 1.2 API Reference

```swift
// Basic glass on a toolbar (automatic in .toolbar{}, but manual for custom chrome)
.glassEffect(.regular)

// Prominent — use for THE primary navigation element only
.glassEffect(.prominent)

// Interactive — for buttons/controls within glass containers
.glassEffect(.regular.interactive())

// Container — groups glass elements so they share a single glass plane
GlassEffectContainer(spacing: 12) {
    Button("Files") { }
    Button("Emails") { }
}

// Morphing — elements with the same ID in the same namespace morph between states
.glassEffectID("selectedTab", in: namespace)

// Tinting — adds semantic color to glass (use sparingly, for meaning only)
.glassEffect(.regular.tint(.blue))
```

### 1.3 Manifold Application

| Surface | Glass Treatment | Why |
|---------|----------------|-----|
| Top toolbar + tab picker | Automatic via `.toolbar { }` | Already correct — `.principal` placement gets glass for free |
| Track Changes toolbar items | `.toolbarBackground()` with agent color tint when active | Communicates "monitoring is on" without a separate banner |
| Files/Emails sidebar | None — sidebars get glass automatically in macOS 26 | Don't override the system |
| Agent Policy Cards (Overview) | **No glass** — these are content, not navigation | Glass on cards would blur the hierarchy |
| Review Access sheet | Standard sheet material (automatic) | Sheets get their own depth layer |
| Settings window toolbar | Automatic via `Settings { }` scene | System-provided |

**What NOT to do in Manifold:**
- Don't put `.glassEffect()` on `AgentPolicyCard`. It's a content surface.
- Don't put `.glassEffect()` on `SourcesTableView` rows or `DomainsTableView` rows.
- Don't put `.glassEffect()` on the work block status text — it's informational, not navigational.

---

## Part 2: Spring Animations — The Physics of Feeling Native

### 2.1 Why Springs Matter (WWDC23 Session 10158 — "Animate with springs")

Every animation in a native Apple app is a spring. Not a bezier curve. Not a linear interpolation. A spring. This matters because springs preserve velocity — if a user flicks a gesture and you animate the result, a spring carries the momentum naturally. A bezier curve ignores the input velocity, creating a disconnect between touch and response.

The key insight: **springs have exactly two parameters that matter.**

**`duration`** — How long the animation *feels*. Not how long it takes to settle (that's longer), but the perceptual duration. Default: 0.5s.

**`bounce`** — The character of the spring.
- `0.0` — No overshoot. Smooth deceleration. Used for most UI (default).
- `> 0.0` — Overshoots and bounces back. Fun, playful. Keep ≤ 0.4 for UI elements.
- `< 0.0` — Flattened. Reaches target faster than smooth, feels "snappy." Good for quick state changes.

### 2.2 Parameter Cookbook for Manifold

```swift
// DEFAULT — use for 90% of animations. Don't specify parameters.
.animation(.spring, value: someState)
// This gives: response 0.55, dampingFraction 0.825, blendDuration 0

// SNAPPY — for quick toggles, checkbox state, pause/resume
.animation(.snappy, value: isPaused)
// Equivalent to: .spring(duration: 0.35, bounce: -0.15)

// BOUNCY — for delightful moments: onboarding transitions, success states
.animation(.bouncy, value: setupComplete)
// Equivalent to: .spring(duration: 0.5, bounce: 0.3)

// CUSTOM SUBTLE — for sheet presentations, card expansion
.animation(.spring(duration: 0.4, bounce: 0.05), value: sheetPresented)
// Barely perceptible overshoot. Feels "alive" without being playful.

// CUSTOM FIRM — for error shakes, warning emphasis
.animation(.spring(duration: 0.3, bounce: -0.2), value: errorState)
// Arrives fast, no bounce. Urgent.
```

### 2.3 Where to Apply in Manifold

| Animation | Spring Preset | Rationale |
|-----------|--------------|-----------|
| Tab switching (Overview/Files/Emails) | `.spring` (default) | Standard navigation, no drama |
| Agent card connection status dot | `.snappy` | Quick state feedback |
| Pause/Resume access toggle | `.snappy` | Immediate response to user action |
| Track Changes toolbar tint appearing | `.spring(duration: 0.6, bounce: 0.0)` | Slow, smooth — draws attention without startling |
| Review Access sheet presentation | System default (don't override) | Sheets have system springs |
| Undo toast appearing | `.spring(duration: 0.35, bounce: 0.1)` | Slight bounce — "here I am, act fast" |
| Undo toast dismissing | `.spring(duration: 0.25, bounce: -0.1)` | Snappy exit — don't linger |
| Setup Assistant page transitions | `.spring(duration: 0.45, bounce: 0.05)` | Gentle forward momentum |
| Error banner slide-down | `.spring(duration: 0.3, bounce: 0.0)` | Smooth, not playful — this is an error |
| Sidebar selection change | `.snappy` | Immediate response to click |
| Checkbox → Review sheet open | System default | Let the system handle commitment-surface transitions |

### 2.4 Anti-Patterns

**Never use `withAnimation(.easeInOut)` for interactive state changes.** The current `MainView.swift` line 29 uses `.animation(.easeInOut(duration: 0.15), value: commands.isPresented)` for the command palette. This should be `.spring(duration: 0.2, bounce: -0.1)` — snappy and physical, not mathematically smooth.

**Never use `withAnimation(.linear)` for anything the user sees.** Linear motion looks robotic. The only valid use is for infinite progress indicators.

**Don't over-animate.** If something is already a spring and feels right, don't tune it further. The default `.spring` is Apple's considered opinion about what motion should feel like. Override only when you have a specific reason.

---

## Part 3: Transitions & Morphing

### 3.1 Zoom Transitions (WWDC24 Session 10145)

Zoom transitions create spatial continuity — an element in a list "becomes" the detail view. This is what makes Photos.app feel like manipulating physical objects.

```swift
// Source: the element the user taps
NavigationLink(value: source) {
    SourceRow(source: source)
}
.matchedTransitionSource(id: source.id, in: namespace)

// Destination: the detail view
.navigationTransitionStyle(.zoom(sourceID: selectedSource?.id, in: namespace))
```

**Manifold application**: When a user taps a source in `SourcesTableView` and the inspector opens, the row should zoom-transition to the inspector panel. This creates a spatial relationship: "this inspector IS that row, expanded."

### 3.2 Matched Geometry for State Changes

For elements that move between positions (not navigation), use `matchedGeometryEffect`:

```swift
// The agent focus indicator (Claude / Codex / Compare)
// The selection highlight should slide between segments, not jump
@Namespace var agentFocus

// In the segmented control:
if selectedAgent == .claude {
    RoundedRectangle(cornerRadius: 8)
        .fill(.blue.opacity(0.15))
        .matchedGeometryEffect(id: "agentHighlight", in: agentFocus)
}
```

### 3.3 Sheet Morphing with Glass

When a button opens a sheet, the button can morph into the sheet using `glassEffectID`:

```swift
// The "Update Access…" button on AgentPolicyCard
Button("Update Access\u{2026}") { showReview = true }
    .glassEffectID("reviewSheet", in: namespace)

// The Review Access sheet
.sheet(isPresented: $showReview) {
    ReviewAccessSheet()
        .glassEffectID("reviewSheet", in: namespace) // morphs FROM the button
}
```

This is the detail that separates a 4.0 app from a 4.5+ app. The sheet doesn't just appear — it grows from the thing you tapped.

---

## Part 4: Corner Concentricity & Shape Language

### 4.1 The Concentricity Principle (WWDC25 Session 356)

When shapes nest inside each other, their corners must share a common center point. This means inner shapes have tighter radii than outer shapes, and the margin between them is consistent.

```
Outer: cornerRadius 16, padding 8
Inner: cornerRadius 8  (16 - 8 = 8 ✓)
```

SwiftUI provides this automatically with `.concentric`:

```swift
// macOS concentric shapes by control size:
// .mini, .small, .medium → RoundedRectangle (concentric radii)
// .large → Capsule
// .extraLarge → New full-width shape

// For custom containers:
RoundedRectangle(cornerRadius: 12)  // outer card
    .overlay {
        RoundedRectangle(cornerRadius: 8)  // inner element (12 - 4pt padding = 8)
            .padding(4)
    }
```

### 4.2 Manifold Application

**Agent Policy Cards**: The card has `cornerRadius: 12`. Any inner rounded elements (status badges, action button backgrounds) should use `cornerRadius: 8` with 4pt inner padding, or `cornerRadius: 6` with 6pt inner padding. The current "connected" capsule badge is correct — capsules are concentricity-exempt because they self-adjust.

**Review Access Sheet**: The sheet has system-provided corner radius (~16 on macOS). Inner content groups should use `cornerRadius: 10–12`. Don't use `cornerRadius: 16` inside a sheet — it breaks concentricity.

**Setup Assistant Screens**: The inline agent setup cards (`InlineAgentSetup`) use `cornerRadius: 10`. Inner `LiveCheckRow` elements should use `cornerRadius: 6` if they have backgrounds.

---

## Part 5: Toolbar & Navigation Patterns

### 5.1 Toolbar Best Practices (WWDC25 Sessions 323 + 356)

```swift
// Toolbar spacer — pushes items apart without fixed widths
ToolbarSpacer(.fixed)   // small fixed gap
ToolbarSpacer(.flexible) // expands to fill

// Shared background — makes a toolbar group share one glass container
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        Button("Review Changes") { }
        Button("Pause") { }
    }
    .sharedBackgroundVisibility(.visible) // single glass backing
}

// Badge — notification count on toolbar items
ToolbarItem {
    Button("Activity") { }
        .badge(pendingChanges)
}

// Scroll edge effect — how content interacts with toolbar edge
.scrollEdgeEffectStyle(.soft, for: .top) // default on most platforms
.scrollEdgeEffectStyle(.hard, for: .top) // pinned headers, macOS default
```

### 5.2 Manifold's Track Changes Toolbar

The design review's #3 recommendation: move the work block banner into the toolbar. Here's the complete pattern:

```swift
// In MainView, when a work block is active:
.toolbar {
    // Existing tab picker stays at .principal
    ToolbarItem(placement: .principal) {
        Picker("Tab", selection: $selectedTab) { /* ... */ }
            .pickerStyle(.segmented)
    }
    
    // Track Changes status in trailing area
    if let block = store.activeWorkBlock {
        ToolbarItemGroup(placement: .primaryAction) {
            TrackChangesToolbarContent(
                block: block,
                onFinish: { /* ... */ },
                onPause: { /* ... */ },
                onStop: { /* ... */ }
            )
        }
    }
}
// Tint the toolbar when tracking is active
.toolbarBackgroundVisibility(
    store.activeWorkBlock != nil ? .visible : .automatic,
    for: .windowToolbar
)
.toolbarBackground(
    store.activeWorkBlock?.agent == .codex ? Color.purple.opacity(0.08) : Color.blue.opacity(0.08),
    for: .windowToolbar
)
```

The toolbar tint is subtle — 8% opacity. It's enough to create ambient awareness without competing with content. This is exactly how Safari tints its toolbar to match website theme colors.

---

## Part 6: Scroll Edge Effects & Background Extension

### 6.1 Scroll Behavior

When content scrolls under a toolbar, the transition point matters. macOS defaults to `.hard` — an abrupt clip. Most Apple apps on other platforms use `.soft` — a gentle fade.

For Manifold, the recommendation:

```swift
// Files table and Emails table — use soft edge
ScrollView {
    SourcesTableView()
}
.scrollEdgeEffectStyle(.soft, for: .top)

// Overview (no scrolling under toolbar typically) — leave default
```

### 6.2 Background Extension

Sidebar content can extend behind the toolbar using `.backgroundExtensionEffect`. This creates visual continuity between the sidebar and toolbar glass:

```swift
// In FilesSidebar or EmailSidebar:
List(selection: $selectedSource) {
    ForEach(sources) { source in
        SourceRow(source: source)
    }
}
.backgroundExtensionEffect()  // extends behind toolbar
```

This is what makes Finder's sidebar feel like a single continuous surface rather than a content area clipped by a toolbar.

---

## Part 7: What Makes Pixelmator Pro Feel Like an Apple App

### 7.1 The Pixelmator Philosophy

Pixelmator Pro won Mac App of the Year 2018 and Apple Design Awards in 2011 and 2019. Their stated philosophy: "power without complexity." Concretely, this means:

**Every feature has exactly one surface.** You never wonder "where do I find X?" In Pixelmator, color adjustment is always in the right sidebar. Layers are always in the left sidebar. Tools are always in the toolbar. There is zero feature duplication across surfaces. Manifold already follows this: Overview answers "what can AI see?", Files manages file access, Emails manages email access. No overlap.

**Progressive disclosure, not feature hiding.** Pixelmator shows the most common controls at the top level. Advanced options are in disclosure groups or secondary tabs. They're always *findable* but never *in the way*. Manifold's disclosure groups in connection sheets (showing file paths, config details) are this pattern.

**Native controls everywhere.** Pixelmator doesn't build custom sliders, custom checkboxes, or custom text fields. They use AppKit/SwiftUI standard controls. This means their app automatically gets system accessibility, keyboard navigation, and visual updates for free. Manifold should follow suit — no custom toggle switches, no custom checkboxes, no custom text inputs.

**Zero configuration for the default case.** Pixelmator opens and you can start editing immediately. Setup is deferred until you need a feature that requires it. Manifold's Setup Assistant should follow this: if the user opens the app and Claude is already connected (ConfigWriter already ran), skip straight to the main interface. Only show setup for what's missing.

### 7.2 The Delight Details

What separates a 4.0 app from an Apple Design Award winner:

**Responsive to every input modality.** Keyboard shortcuts for every action. Menu bar items for every feature. Right-click context menus on every element that has actions. Drag and drop where it makes sense. Manifold's command palette (⌘K) is good, but every agent card action should also be in the menu bar and right-click menu.

**Animations that communicate, not decorate.** Pixelmator's layer reorder animates because it helps you understand where the layer went. Their crop handles animate because it shows you the new frame. Nothing animates just to look cool. In Manifold: animate the connection status dot because it communicates "this just changed." Don't animate the card border because nothing is changing — it's static decoration.

**State transitions that acknowledge the user.** When Pixelmator finishes an export, there's a brief checkmark. When an effect is applied, the preview updates smoothly. Every action gets acknowledged. In Manifold: when "Pause Access" is tapped, the status dot should animate from colored to gray with a brief pulse. When access is broadened after review, the source count should animate up (countingAnimation). These micro-acknowledgments build trust.

**Empty states that educate.** Pixelmator's empty canvas isn't blank — it tells you what to do. Manifold's `emptyState` in OverviewView is reasonable but could be better. Instead of "Manifold will appear here when Claude or Codex connects via MCP," consider something actionable: "Connect an AI agent to get started" with a button that opens the setup flow.

---

## Part 8: Accessibility as Design Excellence

### 8.1 Why This Section Exists

Every Apple Design Award winner ships with full accessibility. It's not an afterthought — it's a design requirement. VoiceOver, Dynamic Type, reduced motion, and increased contrast are all conditions your app must handle gracefully.

### 8.2 Manifold-Specific Requirements

```swift
// Respect reduced motion — use crossfade instead of springs
@Environment(\.accessibilityReduceMotion) var reduceMotion

.animation(reduceMotion ? .none : .spring, value: state)

// VoiceOver: every interactive element needs a label
.accessibilityLabel("Pause access for Claude")
.accessibilityHint("Temporarily stops Claude from reading your files and emails")

// Dynamic Type: use system text styles, not fixed sizes
.font(.callout)      // ✓ scales with Dynamic Type
.font(.system(size: 14)) // ✗ fixed size, doesn't scale

// Agent Focus control — identified as missing in design review
Picker("Agent Filter", selection: $agentFocus) {
    Text("Claude").tag(AgentFocus.claude)
    Text("Codex").tag(AgentFocus.codex)
    Text("Compare").tag(AgentFocus.compare)
}
.accessibilityHint("Shows \(agentFocus.displayName) access columns in the table")

// Undo toast — persist for VoiceOver users
.onChange(of: showUndoToast) {
    if showUndoToast {
        let persistForVoiceOver = NSWorkspace.shared.isVoiceOverEnabled
        if !persistForVoiceOver {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                withAnimation { showUndoToast = false }
            }
        }
        // VoiceOver: toast stays until dismissed or ⌘Z pressed
    }
}
```

---

## Part 9: Performance Patterns That Feel Instant

### 9.1 Perceived Performance

Pixelmator feels fast not because every operation completes instantly, but because the UI never freezes. The principles:

**Never block the main thread.** Every file system read, every database query, every network call is async. The UI shows a lightweight placeholder (not a spinner) during the gap. If the gap is < 200ms, don't show anything — the result arrives before the user notices.

**Prefetch what you'll need.** When the user switches to the Files tab, start loading the Emails data in the background. When a sheet is about to present, compute its content before the animation starts, not after.

**Debounce rapid state changes.** The design review caught this for `IntegrationHealthModel`. The pattern is general:

```swift
// Generic debounce for any expensive check
actor DebouncedCheck {
    private var lastRun: Date?
    private let interval: TimeInterval
    
    init(interval: TimeInterval = 5.0) {
        self.interval = interval
    }
    
    func shouldRun(force: Bool = false) -> Bool {
        if force { lastRun = Date(); return true }
        guard let last = lastRun else { lastRun = Date(); return true }
        if Date().timeIntervalSince(last) >= interval {
            lastRun = Date()
            return true
        }
        return false
    }
}
```

### 9.2 List Performance for Large Data Sets

The Domains table could have hundreds of entries. SwiftUI `List` is lazy by default, but sorting and filtering need care:

```swift
// Compute sorted/filtered results off main actor
@Observable @MainActor
class DomainModel {
    private(set) var displayedDomains: [DomainSummary] = []
    
    func recompute(filter: String, sortOrder: SortOrder) {
        Task.detached { [domains = self.allDomains] in
            let filtered = domains.filter { /* ... */ }
            let sorted = filtered.sorted { /* ... */ }
            await MainActor.run {
                self.displayedDomains = sorted
            }
        }
    }
}
```

---

## Part 10: WWDC Session Reference

### Essential Viewing (In Priority Order)

| Session | Title | Key Takeaway for Manifold |
|---------|-------|--------------------------|
| WWDC25 219 | Meet Liquid Glass | Glass only on chrome. Never glass-on-glass. Regular > Prominent. |
| WWDC25 323 | Build a SwiftUI app with the new design | Complete API reference: glassEffect, toolbar patterns, concentricity |
| WWDC25 356 | Get to know the new design system | Shape system, scroll edge effects, sidebar behavior, sheet focus |
| WWDC23 10158 | Animate with springs | Bounce parameter, presets, velocity preservation |
| WWDC24 10145 | Enhance your UI animations and transitions | Zoom transitions, SwiftUI↔UIKit animation bridge |
| WWDC25 256 | What's new in SwiftUI | @Animatable macro, performance (6x faster lists), windowResizeAnchor |

### Supplementary

| Session | Title | Relevance |
|---------|-------|-----------|
| WWDC25 | Working with Liquid Glass | Advanced: custom shapes, backward compatibility patterns |
| WWDC24 | Demystify SwiftUI containers | ForEach/container patterns for custom layouts |
| WWDC23 | Wind your way through advanced animations | Phase/keyframe animations for complex sequences |
| WWDC22 | The SwiftUI cookbook for navigation | NavigationSplitView patterns (already implemented) |

---

## Part 11: Implementation Checklist — Manifold Surfaces

This is the concrete "do this" list. Each item maps to a specific view file.

### MainView.swift
- [ ] Replace `.easeInOut` command palette animation with `.spring(duration: 0.2, bounce: -0.1)`
- [ ] Add `.scrollEdgeEffectStyle(.soft, for: .top)` to content scroll views
- [ ] Add Track Changes toolbar items per Phase A of implementation plan
- [ ] Add `.toolbarBackground()` tinting when work block is active

### OverviewView.swift
- [ ] Rename "Track Changes" button (already in plan)
- [ ] Improve empty state: add actionable "Connect an AI Agent" button that opens setup
- [ ] Add `.animation(.snappy)` to agent card connection status changes
- [ ] Add counting animation to source count changes on agent cards

### AgentPolicyCard.swift
- [ ] Remove `@State pauseHovered` if it exists — use `Button(role: .destructive)` (already in plan)
- [ ] Shorten "Review & Update Access" → "Update Access…" (already in plan)
- [ ] Add `.animation(.snappy)` to connection status dot color
- [ ] Add `.matchedTransitionSource` to "Update Access…" button for sheet morphing
- [ ] Ensure concentricity: inner badge `cornerRadius` < outer card `cornerRadius` by padding amount

### WorkBlockBannerView.swift (kept as fallback)
- [ ] Rename labels per plan
- [ ] If kept as non-toolbar fallback, replace `.regularMaterial` background with flat `.background(.secondary.opacity(0.06))` — material inside content area reads as chrome, not content

### ReviewAccessSheet.swift
- [ ] Add `.glassEffectID` for morph-from-button transition
- [ ] Sheet title: "Review & Update Access" (longer form, appropriate for sheet titles)

### FilesSidebar / EmailSidebar
- [ ] Add `.backgroundExtensionEffect()` for sidebar-toolbar visual continuity

### SourcesTableView / DomainsTableView
- [ ] Ensure NO glass effects on table rows
- [ ] Add `.animation(.snappy)` to row check state changes
- [ ] DomainsTableView: lazy loading, off-main-actor sort/filter

### Setup Assistant (SetupView.swift, new screens)
- [ ] Page transitions: `.spring(duration: 0.45, bounce: 0.05)`
- [ ] "Continue" and "Done" button labels (not "Get Started" / "Open Manifold")
- [ ] Inline agent checks (no nested sheets)
- [ ] Multi-select folder picker with single review for initial setup
- [ ] Respect `accessibilityReduceMotion` on all page transitions

### Settings (new)
- [ ] Use SwiftUI `Settings { }` scene — auto-sizes per pane
- [ ] Component version footer in Storage pane
- [ ] Health check debouncing (5-second cache)
- [ ] Connection sheets: 2 footer buttons only (Done + Cancel), inline ↻ refresh

### Global
- [ ] Audit all `withAnimation` calls — replace bezier curves with springs
- [ ] Audit all `.opacity` transitions — replace with `.transition(.move.combined(with: .opacity))`
- [ ] Add `@Environment(\.accessibilityReduceMotion)` check wherever custom animations are used
- [ ] Ensure all interactive elements have `.accessibilityLabel()` and `.accessibilityHint()`
- [ ] Add ⌘Z undo support as fallback for time-limited undo toasts

---

## Part 12: The Quality Bar — Self-Assessment Questions

Before considering any view "done," ask these questions. If any answer is "no," the view isn't finished.

1. **Can I use this view entirely with the keyboard?** Tab between elements, Enter to activate, Escape to dismiss.
2. **Does VoiceOver read this view in a logical order?** Labels, hints, groupings.
3. **Are all animations springs?** No bezier curves, no linear, no custom timing functions.
4. **Does this view respect Reduced Motion?** Falls back to crossfade or no animation.
5. **Is glass used only on navigation chrome?** No glass on content surfaces.
6. **Are inner corner radii smaller than outer?** Concentricity check.
7. **Does every state change have a visual acknowledgment?** Connection, pause, error, success.
8. **Is every button label ≤ 3 words?** If longer, it belongs in a sheet title, not a button.
9. **Would this work at 2x the data?** 200 sources, 500 domains, 10 email accounts.
10. **Does this view do zero work on appear if it was visible < 5 seconds ago?** Debounce check.
