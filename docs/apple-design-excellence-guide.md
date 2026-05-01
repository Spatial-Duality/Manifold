# Manifold - Apple Design Excellence Guide v2

> Purpose: align Manifold's visual polish with Apple's documented APIs and the app's current state on `main`.
>
> Scope: Swift 6, SwiftUI, macOS 26. This is a delta plan for the shipped architecture, not a greenfield redesign.

---

## 1. Current Baseline

These items are already on `main` and should be treated as the starting point, not future work:

- Track Changes is already integrated into the toolbar via `MainView` and `TrackChangesToolbarContent`.
- `Review AccessSheet` already uses the correct long-form title: `Review & Update Access`.
- `AgentPolicyCard` already uses the shorter `Update Access...` action label.
- `WorkBlockBannerView` already updates elapsed time live and is now a fallback, not the primary status surface.
- `FilesView` already debounces rapid reload triggers.
- `SourcesTableView` and `DomainsTableView` already track and cancel undo timer tasks.
- `DomainsTableView` already recomputes domain aggregates off the main actor.

The goal of this document is to tighten what remains, not to re-plan completed work.

---

## 2. Platform Rules We Will Follow

### 2.1 Liquid Glass

For Manifold, we will default to Liquid Glass on navigation and overlay chrome only:

- System toolbar chrome
- Standard sidebars and split-view chrome
- Optional custom overlay surfaces like the command palette or transient error chrome

We will not add custom glass to:

- content cards
- table rows
- inspector content
- data summaries

This is an app-level rule, not a universal platform prohibition. Apple explicitly supports custom Liquid Glass views, but in Manifold the trust hierarchy is clearer when content remains solid and chrome remains ambient.

### 2.2 Motion

Prefer native spring families for user-visible state changes:

- `.spring` for standard navigation and structural changes
- `.snappy` for quick feedback like toggles or status changes
- `.bouncy` only for explicitly celebratory moments
- `Animation.spring(duration:bounce:)` only when we need a specific feel

Do not describe `.snappy` or `.bouncy` as exact equivalents of custom `spring(duration:bounce:)` values. Use the named presets directly unless there is a measured reason not to.

### 2.3 Transitions

Use the platform's default transitions unless the current presentation model supports a documented enhancement:

- Keep system sheet transitions for sheets.
- Keep system inspector transitions for inspectors.
- Use `matchedGeometryEffect` only for in-place state movement inside the same view hierarchy.
- Use `matchedTransitionSource` and `navigationTransition(...)` only for actual navigation destinations.

This means two things are out of scope for the current app architecture:

- row-to-inspector zoom transitions
- button-to-sheet Liquid Glass morphs

### 2.4 Background Extension

`backgroundExtensionEffect()` is not a generic "make sidebars feel premium" modifier. Use it only when a specific background surface should visually extend under adjacent safe-area or split-view chrome, and only after visual testing.

For Manifold, do not plan it on the sidebar lists themselves. If we use it at all, it should be on a detail-side background or hero surface that benefits from extension.

### 2.5 Accessibility

Every polish pass must preserve:

- keyboard-first interaction
- VoiceOver labels and hints
- Reduced Motion support
- standard system controls where available
- non-color-only state signaling

---

## 3. What Not To Build

These ideas should be removed from the implementation plan:

- No `.navigationTransitionStyle(...)` work. The relevant API is `navigationTransition(...)`, and it does not apply cleanly to Manifold's current inspector flow.
- No `glassEffectID` plan for sheet presentation. That API is for Liquid Glass view transitions in supported hierarchies, not a general sheet-morph tool.
- No custom segmented control just to get a matched-geometry highlight. The current system segmented control is already the right baseline.
- No blanket `backgroundExtensionEffect()` pass across sidebars.
- No new glass on `AgentPolicyCard`, `SourcesTableView`, or `DomainsTableView`.

---

## 4. Recommended Work By Priority

### P0 - Finish the motion cleanup

These are small, low-risk changes with immediate payoff:

1. Replace remaining `.easeInOut` animations in `MainView` with spring-based motion.
   - Command palette presentation should feel snappy and physical.
   - Error banner presentation should use a simple spring, not a bezier fade.

2. Replace `.easeInOut` transitions in `SetupAssistantView`.
   - Use a spring for screen changes.
   - Gate custom motion with `@Environment(\.accessibilityReduceMotion)`.

3. Keep system transitions for sheets and inspectors.
   - Do not add custom presentation choreography until the underlying architecture supports it naturally.

### P1 - Improve the active-state chrome

This is the strongest visual polish opportunity that fits the current design:

1. Add subtle toolbar ambient tint when a work block is active.
   - Use `toolbarBackground` and `toolbarBackgroundVisibility`.
   - Keep tint extremely light so it reads as awareness, not branding.
   - Color should follow the active agent.

2. Keep Track Changes toolbar-first.
   - Do not promote the fallback banner back into the primary experience.
   - If we add acknowledgements for pause/resume/finish, keep them concise and Reduced-Motion safe.

### P1 - Improve Overview polish without changing layout

1. Upgrade the disconnected empty state in `OverviewView`.
   - Replace passive copy with an actionable CTA that opens setup.
   - Keep the surface calm and instructional.

2. Add lightweight motion to `AgentPolicyCard`.
   - Status dot color changes: `.snappy`
   - Count updates: prefer `contentTransition(.numericText())` if it reads clearly
   - Avoid decorative border or card-scale animations

3. Keep `AgentPolicyCard` as a content card.
   - No Liquid Glass
   - No floating chrome treatment

### P2 - Accessibility and trust feedback

1. Audit all custom animations for Reduced Motion support.
2. Add or verify accessibility labels and hints on every custom interactive control.
3. Ensure time-limited undo surfaces are not the only recovery path.
   - Keyboard undo should exist where the action model supports it.
   - Do not rely solely on a disappearing toast for reversibility.

### P2 - Optional visual experiments

These are experiments, not committed roadmap items:

1. Evaluate `backgroundExtensionEffect()` on a detail-side background surface only.
2. Evaluate whether the command palette should use the existing custom glass helper on macOS 26+.
3. Evaluate whether the toolbar grouping benefits from `ToolbarSpacer` or shared-background behavior after the active-state tint lands.

Only keep these if they improve clarity on device.

---

## 5. Surface-by-Surface Checklist

### MainView.swift

- [x] Toolbar-centered tab picker
- [x] Track Changes toolbar content
- [ ] Replace command palette `.easeInOut` with spring motion
- [ ] Replace error banner `.easeInOut` with spring motion
- [ ] Add subtle active-work-block toolbar tint

### OverviewView.swift

- [ ] Improve disconnected empty state with a setup CTA
- [ ] Add light status/count motion where it communicates real change
- [ ] Keep layout and information architecture unchanged

### AgentPolicyCard.swift

- [x] `Update Access...` label is already shortened
- [ ] Animate status dot changes with `.snappy`
- [ ] Consider numeric text transition for source/domain counts
- [ ] Audit corner rhythm only if a new nested background is introduced
- [x] Keep card as non-glass content

### TrackChangesToolbarContent.swift

- [x] Primary active-session surface already lives in the toolbar
- [ ] Add ambient toolbar tint from the parent scene
- [ ] Keep controls concise and standard
- [ ] Do not add extra chrome inside already-glass toolbar surfaces

### WorkBlockBannerView.swift

- [x] Live elapsed time already fixed
- [ ] Keep only as fallback / secondary surface
- [ ] If shown in content, use a flat content-style background instead of glass-like chrome

### ReviewAccessSheet.swift

- [x] Title already reads `Review & Update Access`
- [x] Keep system sheet presentation
- [ ] Do not add unsupported sheet morphing work

### FilesSidebar / EmailSidebar

- [x] Native sidebar structure is already the correct baseline
- [ ] Do not add custom glass
- [ ] Do not add `backgroundExtensionEffect()` directly to the list without visual proof

### SourcesTableView / DomainsTableView

- [x] No glass rows
- [x] Undo timers are tracked and cancelled
- [x] Domain aggregation already moves work off the main actor
- [ ] Add motion only where it improves change acknowledgement, not row decoration

### FilesView.swift

- [x] Debounced reloads are already in place
- [ ] Avoid adding animation to filtering/sorting unless it measurably improves comprehension

### SetupAssistantView.swift

- [x] Inline setup flow with no nested sheets
- [ ] Replace remaining bezier animations with spring motion
- [ ] Respect `accessibilityReduceMotion`
- [x] Current button labels are already in the right direction (`Continue`, `Back`)

### Settings

- [ ] When implemented, use a native `Settings {}` scene
- [ ] Prefer system layout and sizing behavior over custom window choreography

---

## 6. Implementation Order

1. Motion cleanup in `MainView` and `SetupAssistantView`
2. Toolbar active-state tint and final Track Changes polish
3. Overview empty-state improvement
4. Agent card micro-feedback
5. Accessibility pass
6. Optional background-extension or custom-glass experiments only after the above ship cleanly

---

## 7. Review Bar For Any New UI Change

Before calling a view "done," answer yes to all of these:

1. Does it preserve the current information architecture?
2. Does it use system controls unless there is a clear product reason not to?
3. Does it respect Reduced Motion?
4. Does it avoid new main-thread work?
5. Does it keep glass on chrome by default, not content?
6. Does it improve clarity, not just visual flourish?
7. Does it still work with keyboard navigation and VoiceOver?
8. Does it hold up with more data, not just the happy path?

If any answer is no, the change is not design-excellence work yet.

---

## 8. Apple References

Primary references used to shape this v2 plan:

- [Liquid Glass overview](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [SwiftUI updates - June 2025](https://developer.apple.com/documentation/updates/swiftui)
- [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [glassEffectTransition(_:)](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition%28_%3A%29)
- [Landmarks: Applying a background extension effect](https://developer.apple.com/documentation/swiftui/landmarks-applying-a-background-extension-effect)
- [toolbarBackground(_:for:)](https://developer.apple.com/documentation/swiftui/view/toolbarbackground%28_%3Afor%3A%29-7lv0f?changes=_8)

Use Apple docs as the tie-breaker whenever a design idea sounds appealing but the API behavior is ambiguous.
