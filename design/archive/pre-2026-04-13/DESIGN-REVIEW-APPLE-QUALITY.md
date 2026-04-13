# Manifold v4.1 Design Review — Native Apple App Quality Bar

> **Benchmark**: System Settings, Mail.app, Finder, Photos, Xcode. These are the standard. A good macOS app feels like it was made by someone who uses a Mac every day and has internalized Apple's opinions about how software should behave.
>
> **Scoring**: Each dimension rated 1–5. 1 = doesn't meet the bar. 3 = acceptable but with rough edges. 5 = indistinguishable from a first-party Apple app.

---

## Overall Score: 3.8 / 5

This is a well-designed macOS app with strong conceptual clarity. The trust-boundary-as-UI principle is genuinely good product thinking — it's the kind of insight Apple would arrive at. The Intentionality Rule (broadening always goes through a commitment surface) mirrors Apple's own privacy model. Several areas need tightening to close the gap from "good indie app" to "feels like it shipped with the OS."

---

## Dimension Scores

### 1. Information Architecture — 4.5 / 5

**What's right**: Three tabs with clear jobs. Overview answers "what can AI see?", Files manages file access, Emails manages email access. One concept per surface. No overlap. The sidebar-as-mode-switch pattern (source list → file browser vs. deselect → sources table) is exactly how Finder works (sidebar selects, detail changes). The Agent Focus segmented control (Claude / Codex / Compare) is borrowed from Xcode's scheme selector — the right level of complexity for power users without confusing novices.

**What's slightly off**: The relationship between the Overview agent cards and the Review & Update Access sheet isn't immediately obvious from the architecture alone. In Mail.app, you never wonder "where do I go to change this?" — the affordance is always in context. The agent cards have a "Review & Update Access" button, which is good, but the button text is long. Apple would probably use a shorter label with an SF Symbol and let the sheet title do the explaining.

**Suggestion**: Consider shortening the card button to "Update Access…" (the ellipsis signals a sheet will open — Apple convention). The sheet title already says "Review & Update Access."

### 2. Navigation Model — 4.0 / 5

**What's right**: The 3-tab segmented control in the top bar is correct macOS idiom. System Settings uses exactly this pattern (sidebar categories, but the top-level conceptual model is the same). Files and Emails having their own `NavigationSplitView` is correct — Finder does this, Mail does this. Overview being full-width with no sidebar is right — it's a dashboard, not a drill-down surface.

**What needs work**: The work block banner sitting between the top bar and tab content is unusual. No Apple app has a persistent alert-style strip in this position. The closest analogue is Mail's "This message is from a mailing list" banner, which sits inside the content area, not between chrome and content. The banner breaks the glass-to-content visual flow.

**Suggestion**: Consider making the work block banner a modification of the top bar itself (the bar tints blue/purple when a work block is active, and the controls move into the top bar trailing area) rather than a separate strip. This is how Safari handles downloads — the indicator is in the toolbar, not a separate bar. Alternatively, if the banner must be separate, it should have no background (just inline text + buttons) so it reads as content, not chrome.

**Second issue**: The Activity Drawer replacing the Inspector is potentially confusing. In Xcode, the inspector and the debug area are independent panels. Having them mutually exclusive means "I'm looking at file details" and "I want to see activity" become competing actions. On a large display this is unnecessary friction.

### 3. Visual Design & Material — 4.0 / 5

**What's right**: Liquid Glass on chrome only. Stable opaque for data rows. This is the correct discipline — the v4.0 wireframe over-applied glass. The color language (blue = Claude, purple = Codex, green = connected, orange = warning) is clear and consistent. The left-border accent on agent cards is a nice touch that creates visual hierarchy without being heavy. Row tinting for checked items in the agent's color is subtle and effective.

**What needs work**: The 3pt left border on agent cards is not an Apple pattern. Apple uses indentation, opacity, and SF Symbol weight to create hierarchy — not colored borders. The closest Apple analogue is the sidebar selection highlight, which is a full-row tint, not a border. The colored border reads more like Material Design than Apple HIG.

**Suggestion**: Replace the left border with a subtle full-background tint (agent color at 4% opacity) and use the agent's colored dot + bold text as the primary hierarchy signal. This is how Mail.app handles VIP markers — the dot is the signal, not a border.

**Second issue**: The spec calls for `.glassEffect()` on the top bar, but the implementation plan shows tabs integrated directly into MainView without a dedicated TopBarView. If the tab segmented control is just a regular `Picker` without glass backing, it will look flat and disconnected from the window chrome. System Settings integrates its navigation into the window toolbar — Manifold should do the same using `.toolbar { }` with `ToolbarItem(placement:)` to get automatic glass treatment.

### 4. Interaction Design — 4.5 / 5

**What's right**: The Intentionality Rule is the star of this design. Broadening always goes through a commitment surface (the Review sheet). Narrowing is immediate with undo. This is Apple's privacy model transplanted into an access control UI. It's the correct mental model. The undo toast for narrowing is exactly how Apple handles destructive-but-reversible actions (delete in Mail, archive in Messages). The AccessCheckbox that opens a sheet instead of toggling is genuinely clever — it makes the grant feel deliberate.

**What's slightly off**: The sheet opening on every broadening checkbox is potentially fatiguing. If I'm setting up access for the first time and want to add 5 folders, I'll open the Review sheet 5 times. Apple's Files provider model handles this with a single "Select Folders" picker that returns multiple selections, then one confirmation. The per-checkbox sheet is correct for protecting individual grants after setup, but during initial setup it creates friction.

**Suggestion**: The Setup Assistant's "Add Your Data" screen should use a multi-select folder picker that adds everything at once with a single review. The per-checkbox-triggers-sheet behavior is correct for the Files tab during normal use. This distinction already exists in the design (Setup Assistant vs. Files tab) but should be called out explicitly: Setup Assistant bypasses the per-item Review sheet because the entire screen IS the review context.

**Second issue**: "Pause Access" as a button on the agent card that turns red on hover is unusual. Apple doesn't change button color on hover for destructive actions — it uses `.role: .destructive` which makes the button red by default. The hover-to-reveal-danger pattern is web design, not macOS.

### 5. Settings & Preferences — 4.0 / 5

**What's right**: Four tabs is correct. System Settings uses simple tab structure for focused apps. The AI Apps pane with two agent cards showing live health checks is a strong pattern — it's how Network preferences shows interface status. Re-checking on every pane load (Rule 6) is what System Settings does with Wi-Fi, Bluetooth, etc.

**What needs work**: The Settings window at 520×460 may be tight for the AI Apps pane with two full agent cards (each with 2–3 check rows, disclosure groups, and action buttons). System Settings gives individual panes room to breathe — the typical pane is 600+ pixels wide. The Mail pane with account list + storage stats + add/remove will feel cramped at 520.

**Suggestion**: Consider 580×500 minimum, or use the macOS Settings scene which auto-sizes per pane. SwiftUI's `Settings { }` scene handles this natively.

**Second issue**: The "About" information is removed entirely, with version info relegated to the standard macOS About window. This is correct for most apps, but Manifold has a component ecosystem (MCP binary version, ConfigWriter schema version, ManifoldKit version) that power users will want to see. Consider a small "Manifold v0.3.0 · MCP v1.2" line in the Storage pane footer, similar to how Xcode shows component versions in its About window.

### 6. First-Run / Onboarding — 3.5 / 5

**What's right**: Four screens is the right count. The progression (welcome → connect → add data → done) matches how Apple onboards complex apps (Xcode: welcome → install components → select project). Progress dots instead of a progress bar is correct — Apple uses dots for short flows, bars for long ones. "One sentence per screen" is the right discipline. The skip options on non-critical screens are essential.

**What needs work**: The Setup Assistant presents connection sheets as sub-sheets (sheet within sheet). This is technically valid in SwiftUI but creates a jarring experience — the user sees a sheet slide up, then another sheet slide up on top of it. Apple avoids nested sheets in onboarding flows. Xcode's "Install Components" step shows the progress inline, not in a sub-sheet.

**Suggestion**: Instead of opening ConnectClaudeSheet as a `.sheet()` from the Connect Apps screen, inline the live check rows directly into the Setup Assistant screen. The assistant screen becomes the sheet. The separate ConnectClaudeSheet/ConnectCodexSheet should exist for the Settings context (where they make sense as standalone modals) but the Setup Assistant should present the same checks inline. This eliminates the nested-sheet problem.

**Second issue**: The "Get Started" button on the Welcome screen is generic. Apple's onboarding screens use context-specific primary actions: "Continue" (straightforward), "Set Up" (something to configure), or the specific action itself. "Get Started" is startup-speak. "Continue" would be more Apple.

**Third issue**: Screen 4's headline "You're ready." ends with a period, which is correct, but the button "Open Manifold" is misleading — the user is already in Manifold. The button should be "Done" or "Finish Setup" to match what it actually does (dismiss the sheet). System Settings uses "Done" for this pattern.

### 7. Connection Sheets — 3.5 / 5

**What's right**: Live check rows with status icons are a strong pattern. The progressive disclosure of technical details (paths, config files) is correct per Rule 5. The two-path Claude install (ConfigWriter as primary, .mcpb as manual alternative) is pragmatic. Surfacing Codex stderr directly is honest and useful.

**What needs work**: The sheets show "Check Again" as a separate button alongside "Done" and "Cancel." This is three buttons in the footer. Apple's sheet convention is one primary, one cancel. "Check Again" should be inline (perhaps a refresh icon next to the status that failed) rather than a footer button. Three buttons in a sheet footer creates decision paralysis.

**Suggestion**: Remove "Check Again" from the footer. Add a small refresh button (↻) next to each check row that failed. The "Done" button is the primary. "Cancel" is the secondary. This is two buttons, which is correct.

**Second issue**: The ConnectClaudeSheet at 460×420 and ConnectCodexSheet at 460×380 are close enough in size that the visual difference will be noticed but feel like a bug rather than a feature. Either make them the same size (460×420 both) or make the size difference dramatic enough to be intentional (460×420 vs. 460×300). The 40px difference looks like someone forgot to update one.

**Third issue**: The install action for Claude opens Finder to reveal the .mcpb file. This takes the user out of the app entirely. If ConfigWriter is the primary path, the "Install" button should run ConfigWriter silently and show a checkmark. The .mcpb revelation should be a secondary "Install manually…" link in the disclosure group, not the primary action.

### 8. Copy & Tone — 4.0 / 5

**What's right**: The copy follows Apple's style — short, declarative, no exclamation marks. "Connected" instead of "Successfully connected!" is correct. "Manifold controls what AI agents see on your Mac" is a clear one-sentence product description. The domain copy ("247 + future mail" for checked, just "15" for unchecked) is smart and information-dense without being noisy.

**What needs work**: "Review & Update Access" is verbose for a primary action. Apple uses 1–3 word button labels: "Allow", "Update", "Continue." The label works as a sheet title but not as a button label that appears on every agent card and in the keyboard shortcut menu.

**Suggestion**: Button label: "Update Access…" (ellipsis = sheet). Sheet title: "Review & Update Access." Menu command: "Review Access…" (⌘⇧R). Three different but consistent forms for three different contexts.

**Second issue**: "Start Tracked Work Block" is jargon. No Apple app asks users to "start a tracked work block." The concept is good (snapshot before AI works, review after), but the naming is internal. Consider "Start Monitored Session" or simply "Track Changes" — both are closer to concepts users already know (Word's Track Changes, Time Machine's snapshots).

### 9. Accessibility — 4.0 / 5

**What's right**: The spec calls for VoiceOver labels on all interactive elements, 44pt touch targets on checkboxes, WCAG AA contrast for hidden rows. The progress dots have `.accessibilityLabel()`. Status icons have accessibility labels ("Found", "Warning", etc.).

**What needs work**: The Agent Focus segmented control (Claude / Codex / Compare) doesn't have a clear accessibility story. VoiceOver users need to understand that switching this control changes what columns appear in the table. The `.accessibilityHint()` should explain: "Switches the table to show access for Claude only."

**Suggestion**: Add `.accessibilityHint("Shows \(mode.displayName) access columns in the table")` to the AgentFocusControl picker.

**Second issue**: The undo toast for narrowing actions is time-limited (presumably 5–10 seconds). VoiceOver users may not reach the undo button in time. Consider making the toast persist until dismissed for VoiceOver users, or providing an undo option in the Edit menu (⌘Z) as a fallback.

### 10. Performance & Responsiveness — 3.5 / 5

**What's right**: The architecture separates data stores (actors in ManifoldKit) from view models (`@Observable @MainActor`). Database access is async. The 5-second connection polling with 300-second timeout is reasonable.

**What needs work**: The IntegrationHealthModel runs `checkAll()` on every Settings pane load, Setup Assistant appear, and connection sheet appear. Each check involves file system reads (checking app paths, reading JSON/TOML config files). This is fine for occasional use, but if the user rapidly switches between Settings tabs, they'll trigger redundant checks. There's no debouncing or caching.

**Suggestion**: Add a simple time-based cache: if `checkAll()` was called less than 5 seconds ago, return cached results. Only force-refresh on explicit "Check Again" action.

**Second issue**: The DomainModel needs to compute aggregates from the email store, which could be large (thousands of emails across hundreds of domains). This computation should be done off the main actor with results delivered back. The spec doesn't address pagination or lazy loading for the Domains table with large domain counts.

---

## Summary by Area

| Dimension | Score | Key Strength | Key Gap |
|-----------|-------|-------------|---------|
| Information Architecture | 4.5 | One concept per surface | Review sheet button label too long |
| Navigation | 4.0 | Correct tab + NavigationSplitView usage | Work block banner placement unusual |
| Visual Design | 4.0 | Correct Liquid Glass discipline | Left-border card accent is non-Apple |
| Interaction | 4.5 | Intentionality Rule is excellent | Per-checkbox sheet fatigue during setup |
| Settings | 4.0 | Live health checks, re-check on appear | Window size may be tight |
| Onboarding | 3.5 | 4 screens, correct progression | Nested sheets, generic CTA labels |
| Connection Sheets | 3.5 | Live checks, honest error surfacing | 3 footer buttons, size inconsistency |
| Copy | 4.0 | Apple-style short declarative tone | "Tracked Work Block" is jargon |
| Accessibility | 4.0 | VoiceOver labels, contrast compliance | Undo toast timing for VoiceOver |
| Performance | 3.5 | Actor-based stores, async access | No check debouncing, no domain pagination |

---

## Top 5 Changes That Would Move the Score to 4.5+

1. **Inline connection checks in Setup Assistant** instead of nested sheets. The biggest UX gap. Show the same LiveCheckRow content directly on the Connect Apps screen. Reserve the standalone sheets for Settings.

2. **Rename "Start Tracked Work Block"** to "Track Changes" or "Start Monitored Session." Drop the internal jargon. This label appears in the Review sheet, Overview, and keyboard shortcuts — it needs to be instantly understood.

3. **Rethink the work block banner** as a top-bar modification rather than a separate strip. Tint the bar, move controls into toolbar items. This preserves the glass-to-content visual flow.

4. **Add debouncing to IntegrationHealthModel** — 5-second cache on `checkAll()`, force-refresh only on explicit action. Prevents redundant filesystem reads on rapid Settings tab switches.

5. **Shorten button labels**: "Update Access…" on cards, "Review & Update Access" as sheet title, "Review Access…" in menu bar. Three forms for three contexts, all shorter than the current single label.

---

## Verdict

Manifold v4.1 is a strong design that gets the hard things right: the trust model, the commitment surface, the information architecture. The gaps are all in the last 20% of polish — copy length, nested modals, banner placement, performance caching. None of these require architectural changes; they're refinement work. The core concept (making the trust boundary visible, making every broadening deliberate) is better product thinking than most shipping Apple apps manage for third-party integrations. With the five changes above, this would feel native.
