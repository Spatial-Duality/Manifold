# Manifold Redesign Plan v5.1

> **Incorporates**: Both rounds of review feedback, the v2 APPLE-DESIGN-EXCELLENCE-GUIDE constraints, and full codebase audit of 47 view files + ManifoldKit models.
>
> **Ground rules from v2 guide**: No custom glass on content. No sheet morphs. No button-to-sheet glass transitions. No blanket backgroundExtensionEffect. Use named spring presets directly. Keep system transitions for sheets/inspectors.
>
> **Priority order**: Based on the corrected priority from both reviews: (1) remove visual noise, (2) fix the shell grammar, (3) fix state truthfulness, (4) rebuild Emails architecture, (5) add meaning layer.
>
> **Scope**: SwiftUI changes only. No model/persistence layer changes unless stated.
>
> **The core diagnosis**: The app has the right backbone. What's missing is hierarchy, spatial discipline, state truthfulness, and the meaning layer. The gap is not conceptual — it's about finishing.

---

## Phase 0: Remove Fake Row Strips (30 minutes)

**The single fastest visual quality improvement possible.**

The Files and Domains screens render dozens of pale rounded horizontal strips below the real data rows. These look like skeleton loaders or placeholder mockups. They are the strongest "prototype" signal in the entire app and must go immediately.

**Root cause**: Likely `alternatesRowBackgrounds: true` combined with a fixed-height container that renders background stripes beyond the actual data rows, or a custom filler view.

**Fix**: In `SourcesTableView`, `DomainsTableView`, and `FilesView`, ensure the list/table does not render placeholder rows. Options:

```swift
// Option A: Remove alternating backgrounds entirely
.listStyle(.inset)  // not .inset(alternatesRowBackgrounds: true)

// Option B: If using Table, ensure it clips to content
.frame(maxHeight: .infinity, alignment: .top)

// Option C: If using a custom row filler, remove it entirely
```

Check every List and Table in the Views directory. If any view is generating filler rows to fill the viewport, remove that code. A native macOS table shows the content it has and then shows empty space — it never fills with fake rows.

**Files to check**: `SourcesTableView.swift`, `DomainsTableView.swift`, `FilesView.swift`, `ActivityView.swift`

---

## Phase 1: Fix the Access-State Model and Copy on Overview

**The problem**: Both agent cards show "Resume Access" in the screenshot. This is either a state bug (both agents are paused and the UI doesn't distinguish) or a copy bug (the label doesn't reflect actual state). In a governance app, ambiguous access state is a trust defect.

**The second problem**: "Pause Access" is the highest-stakes control on the card and it's styled as `.buttonStyle(.plain)` in `.callout` font — visually indistinguishable from "View Activity →".

### 1.1 Fix the access control copy and styling

**File**: `Views/AgentPolicyCard.swift` (118 lines)

Current code (line 111):
```swift
Button(isPaused ? "Resume Access" : "Pause Access", role: isPaused ? nil : .destructive) {
    onPauseToggle()
}
.buttonStyle(.plain)
.font(.callout)
```

**Change to**:
```swift
// Access control — must be visually unmistakable
Toggle(isOn: Binding(
    get: { !isPaused },
    set: { _ in onPauseToggle() }
)) {
    Text("Access")
        .font(.callout)
}
.toggleStyle(.switch)
.tint(agentColor)
.accessibilityLabel(isPaused ? "Access paused for \(agentName)" : "Access active for \(agentName)")
.accessibilityHint("Toggle to \(isPaused ? "resume" : "pause") \(agentName) file and email access")
```

**Why a Toggle instead of a Button**: The access state is binary and persistent. Buttons are for actions; toggles are for states. Every Apple permission surface (System Settings → Privacy, Screen Time, Focus) uses toggles for on/off access. The user should see the *current state* at a glance, not have to read a verb and infer the state from it.

**The toggle color follows the agent** (blue for Claude, purple for Codex) so the user can distinguish which agent's access they're controlling even in peripheral vision.

### 1.2 Fix the "connected" / "disconnected" emphasis inversion

**File**: `Views/AgentPolicyCard.swift` (lines 95-106)

Current: "connected" gets a capsule pill background. "disconnected" gets bare tertiary text.

**Change to**:
```swift
if isConnected {
    // Happy state is quiet — just the colored dot communicates it
    Text("Connected")
        .font(.caption)
        .foregroundStyle(.secondary)
} else {
    // Problem state is louder — pill with warm tint
    Label("Not Connected", systemImage: "exclamationmark.circle")
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.orange.opacity(0.12), in: Capsule())
}
```

**Rationale**: The state that requires action gets the visual weight. The state that's fine recedes. This matches Little Snitch, 1Password Watchtower, and Apple's own Privacy indicators.

### 1.3 Fix "No email access" passivity

**File**: `Views/AgentPolicyCard.swift` (lines 40-55)

Current: `Text("No email access").font(.callout).foregroundStyle(.tertiary)`

**Change to**:
```swift
if emailAccountCount > 0 {
    // existing code
} else {
    Button {
        // Navigate to Emails tab
        store.selectedTab = .emails
    } label: {
        HStack(spacing: Spacing.tight) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Text("Set up email access")
                .font(.callout)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    .buttonStyle(.plain)
}
```

**Rationale**: Every empty state should lead somewhere. "No email access" is a status report. "Set up email access ›" is an invitation.

### 1.4 Fix "View Activity →" Unicode arrow

**File**: `Views/AgentPolicyCard.swift` (line 62)

Change `"View Activity \u{2192}"` to:
```swift
Label("Activity", systemImage: "waveform.path")
    .font(.callout)
    .foregroundStyle(.secondary)
```

Shorter label, SF Symbol, consistent with the rest of the app's icon language.

### 1.5 Fix Track Changes button styling

**File**: `Views/OverviewView.swift` (lines 21-32)

Current: `.controlSize(.large)` + `.buttonStyle(.plain)` + `.foregroundStyle(.secondary)` — conflicting signals.

**Change to**:
```swift
Button {
    reviewSheetChange = ReviewAccessChange(
        description: "Start tracking changes",
        kind: .startWorkBlock
    )
} label: {
    Label("Track Changes", systemImage: "timeline.selection")
}
.buttonStyle(.bordered)
.controlSize(.regular)
```

No longer `.large` + `.plain` + `.secondary`. Now `.bordered` + `.regular` — secondary but visually present. The system handles the rest.

---

## Phase 2: Redesign Major Layouts — One Clear Primary Surface Per Screen

### 2.1 Overview: Fill the dead space with trust context

**The problem**: Two thin cards in 70% empty space. The user can't assess their security posture at a glance.

**File**: `Views/OverviewView.swift` (141 lines)

**Add below the agent cards** (inside the VStack, after `agentCards`):

```swift
// Trust summary — what changed recently
if store.isConnected {
    VStack(alignment: .leading, spacing: Spacing.section) {
        Text("Recent Activity")
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
        
        if let recentEvents = store.recentActivitySummary, !recentEvents.isEmpty {
            ForEach(recentEvents.prefix(5)) { event in
                HStack(spacing: Spacing.standard) {
                    Image(systemName: event.icon)
                        .foregroundStyle(event.color)
                        .frame(width: 16)
                    Text(event.summary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(event.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("No recent activity")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
    .padding(Spacing.edge)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
        RoundedRectangle(cornerRadius: Spacing.cornerLarge)
            .fill(.background)
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
    .overlay {
        RoundedRectangle(cornerRadius: Spacing.cornerLarge)
            .strokeBorder(.separator, lineWidth: 0.5)
    }
}
```

**Model change needed**: Add `recentActivitySummary: [ActivitySummaryItem]?` to `ManifoldStore` that returns the last 5 notable events (file reads, email accesses, grants, revocations). This is a lightweight computed property from existing activity data.

**Why**: The Overview should answer "what can AI see right now AND what did it do recently?" in under 2 seconds. The cards answer the first question. The activity summary answers the second. Together they fill the viewport and build trust.

### 2.2 Files: Eliminate source duplication

**The problem**: Sources appear in the sidebar AND as the default content table. The user sees the same five items twice.

**File**: `Views/MainView.swift` (FilesTab, lines 200-231)

Current flow:
- Sidebar: FilesSidebar shows sources + "Add Folder..." + version sections
- No selection → SourcesTableView (which shows the same sources again as a table)
- Selection → FilesView (file browser for that source)

**Change**: When no source is selected, show a summary landing instead of re-listing sources.

```swift
private struct FilesTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var selection: FilesSidebarSelection?

    var body: some View {
        NavigationSplitView {
            FilesSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            switch selection {
            case nil:
                // Landing: trust summary for files, not a duplicate source list
                FilesLandingView()
            case .source(let source):
                FilesView(sidebarSelection: .source(source))
            case .recentlyModified:
                FilesView(sidebarSelection: .recentlyModified)
            case .aiTouched:
                FilesView(sidebarSelection: .aiTouched)
            case .activity:
                ActivityView()
            }
        }
        .inspector(isPresented: inspectorBinding) {
            if let path = store.inspectedFilePath {
                VersionDetailView(filePath: path)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 480)
            }
        }
    }
}
```

**New file**: `Views/FilesLandingView.swift` (~80 lines)

```swift
/// Files landing when no source is selected in the sidebar.
/// Shows per-source access summary with agent columns.
/// This replaces SourcesTableView as the default content.
struct FilesLandingView: View {
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        List {
            Section {
                ForEach(store.sources.filter { !$0.isRemoved }) { source in
                    HStack {
                        Label(source.displayName, systemImage: source.isDirectory ? "folder.fill" : "doc")
                        Spacer()
                        // Agent access indicators inline
                        agentAccessBadge(for: source, agent: .cowork)
                        agentAccessBadge(for: source, agent: .codex)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("\(store.sources.filter { !$0.isRemoved }.count) Sources")
            }
        }
        .listStyle(.inset)
        .navigationTitle("Files")
        .navigationSubtitle("\(accessedCount) of \(totalCount) accessible")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Folder\u{2026}", systemImage: "folder.badge.plus") {
                    // open NSOpenPanel
                }
            }
        }
    }
}
```

**What this changes**: The sidebar is the navigation index. The content area shows *detail about* the selected item, or a summary landing when nothing is selected. Sources are never listed in both columns simultaneously.

**What happens to SourcesTableView**: It becomes the per-source detail view — when you select a source in the sidebar, it shows that source's files with access checkboxes. It's no longer the default landing.

### 2.3 Settings: Collapse unconfigured agents, fill space

**File**: `Views/Settings/AIAppsSettingsPane.swift`

**Change**: Wrap the Codex section in a `DisclosureGroup` when not configured:

```swift
if codexConfigured {
    // Full Codex section (same as current)
    codexSection
} else {
    DisclosureGroup("Codex") {
        codexSection
    }
    .foregroundStyle(.secondary)
}
```

**Storage pane**: Add a simple proportional indicator:

```swift
// After "Blob storage" row
if let totalDisk = store.totalDiskSpace, totalDisk > 0 {
    VStack(alignment: .leading, spacing: 4) {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.blue)
                        .frame(width: geo.size.width * min(1, Double(blobBytes) / Double(totalDisk)))
                }
        }
        .frame(height: 6)
        Text("\(formattedBlob) of \(formattedTotal)")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
```

### 2.4 AI-Touched Files: Fix filter bar position

**File**: `Views/FilesView.swift`

The filter bar and search must be pinned to the top of the content area, above the list/empty state, not floating below the header. This is likely a layout ordering issue in the VStack/List composition. Ensure the filter controls are in the toolbar or pinned section header, not embedded in scrollable content.

---

## Phase 3: Rework Domains Into a Governance Tool

**The problem**: A flat list of 50+ domains with unexplained "future" text, checkboxes at the far edge, no grouping, and no risk prioritization.

### 3.1 Replace "future" with human-readable policy text

**File**: `Views/Email/DomainsTableView.swift`

Find every instance of the "future" string and replace with the actual policy meaning:

```swift
// Instead of "535 emails · future"
Text("\(domain.emailCount) emails · Incoming visible")
    .font(.caption)
    .foregroundStyle(.secondary)
```

If "future" means "the agent can read new emails from this domain going forward," the UI should say exactly that. If it means something else, say what it means.

### 3.2 Add section grouping

Group domains by category. The simplest approach that doesn't require ML or user configuration:

```swift
// Computed sections based on email volume and known patterns
enum DomainCategory: String, CaseIterable {
    case financial = "Financial"
    case personal = "Personal" 
    case work = "Work"
    case newsletters = "Newsletters & Marketing"
    case other = "Other"
}

// Pattern matching for auto-categorization
func categorize(_ domain: String) -> DomainCategory {
    let financialPatterns = ["bank", "hsbc", "monzo", "creditcard", "virgin money", "halifax", "santander"]
    let newsletterPatterns = ["substack", "beehiiv", "mailchimp", "newsletter", "marketing", "gumroad"]
    let personalPatterns = ["me.com", "icloud", "gmail", "outlook", "live.co", "hotmail"]
    // ... etc
    return .other
}
```

Then render with `Section` headers:

```swift
ForEach(DomainCategory.allCases, id: \.self) { category in
    let domains = groupedDomains[category] ?? []
    if !domains.isEmpty {
        Section(category.rawValue) {
            ForEach(domains) { domain in
                DomainRow(domain: domain)
            }
        }
    }
}
```

### 3.3 Move checkboxes adjacent to domain labels

Current: checkbox is the last column, far right. 

**Change**: Make the checkbox the first column, or use a leading toggle:

```swift
HStack(spacing: Spacing.standard) {
    Toggle("", isOn: domainBinding)
        .toggleStyle(.checkbox)
        .labelsHidden()
    
    VStack(alignment: .leading, spacing: 2) {
        Text("@\(domain.name)")
            .font(.callout.weight(.medium))
        Text("\(domain.emailCount) emails · Incoming visible")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    Spacer()
    
    // Sensitivity indicator (if not default)
    if domain.sensitivity != .moderate {
        Text(domain.sensitivity.displayName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.08), in: Capsule())
    }
}
```

### 3.4 Fix the Domains/Messages navigation toggle

**File**: `Views/MainView.swift` (EmailsTab, lines 239-265)

Current: A text button "View Messages" / "← Domains" toggles between two entirely different views.

**Change**: Make this a sidebar-driven navigation, or at minimum a segmented control:

```swift
private struct EmailsTab: View {
    @State private var emailMode: EmailMode = .domains
    
    enum EmailMode: String, CaseIterable {
        case domains = "Domains"
        case messages = "Messages"
    }
    
    var body: some View {
        Group {
            switch emailMode {
            case .domains:
                DomainsTableView()
            case .messages:
                EmailView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                // This sits alongside the main tab picker or replaces
                // the navigation button with a proper segmented control
                Picker("Email View", selection: $emailMode) {
                    ForEach(EmailMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
}
```

**Problem**: This competes with the main tab picker at `.principal`. Alternative: put the Domains/Messages picker at `.navigation` placement as a secondary segmented control, or use the sidebar for this split.

### 3.5 Declutter the Emails toolbar

Move Sensitivity and Moderate controls out of the toolbar into a filter popover:

```swift
ToolbarItem(placement: .primaryAction) {
    Menu {
        Picker("Sensitivity", selection: $sensitivity) {
            ForEach(EmailSensitivityLevel.allCases) { level in
                Text(level.displayName).tag(level)
            }
        }
        // Other advanced filters
    } label: {
        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
    }
}
```

This reduces the toolbar from 8+ controls to ~5.

---

## Phase 4: Normalize Formatting, Density, and Truncation

### 4.1 Date formatting — use RelativeDateTimeFormatter everywhere

**File**: `Views/Helpers/TimeLabel.swift` + all views that format dates

The codebase already has smart date formatting in `EmailMessageRow.swift` (lines 74-96) with today/yesterday/same-year logic. But other views show raw timestamps or non-standard formats like "18 days, 13 hrs."

**Standard**: Create one shared date formatting utility:

```swift
struct ManifoldDateFormatter {
    static func relative(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
            // "3:42 PM"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else if interval < 7 * 86400 {
            return date.formatted(.relative(presentation: .named))
            // "3 days ago"
        } else if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
            // "Mar 23"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
            // "Mar 23, 2025"
        }
    }
}
```

Apply this everywhere: file modification dates, email timestamps, activity events, version history.

### 4.2 Fix email message row dates

**File**: `Views/Email/EmailMessageRow.swift` (lines 74-96)

The existing ISO8601 parsing is correct but the *display* format shows raw timezone strings in some fallback cases. Ensure all paths through the formatter use the standard `ManifoldDateFormatter.relative()` output.

### 4.3 Fix sidebar truncation

**File**: `Views/MainView.swift` (line 207)

Change sidebar minimum width from 200 to 220:
```swift
.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
```

Also review sidebar label lengths. If "Smart Mailboxes" truncates, consider abbreviating to "Smart" in tight layouts or using `lineLimit(1)` with `.truncationMode(.middle)` for long folder names.

### 4.4 Agent Focus label: rename "Cowork"

**File**: `Views/Helpers/AgentFocusControl.swift` (or wherever the picker labels are defined)

"Cowork" → "All" (if it means all agents combined) or remove it entirely if the default is already "all agents."

The picker should read: `All | Claude | Codex | Compare` — four concepts that are all the same kind of thing (filter scope).

### 4.5 Density normalization

Define a target: each screen should show 8-20 visible information units in its default state.

- **Overview**: Currently ~6 (two cards × 3 lines each). With the activity summary from Phase 2.1, this rises to ~15. Good.
- **Files landing**: Currently shows ~5 source rows. With agent access indicators inline, each row carries more information. Adequate.
- **Domains**: Currently 50+ flat rows. With grouping from Phase 3.2, each section shows 5-15 domains with headers providing orientation. Better.
- **Settings AI Apps**: Currently ~7 check rows. With Codex collapsed when unconfigured, the visible content is ~4-5. The Storage bar from Phase 2.3 helps.

---

## Phase 5: Trust Summary — What Each Agent Can See Now

### 5.1 Agent card visual hierarchy improvement

**File**: `Views/AgentPolicyCard.swift`

Make the source count and email count scannable at a glance by giving them more visual weight:

```swift
// Instead of "2 of 5 sources" as a secondary text line
HStack(spacing: Spacing.tight) {
    Image(systemName: "folder.fill")
        .foregroundStyle(.secondary)
        .imageScale(.small)
    Text("\(sourceCount)")
        .font(.callout.weight(.medium))
        .contentTransition(.numericText())
    Text("of \(totalSources) sources")
        .font(.callout)
        .foregroundStyle(.secondary)
}
```

The *count* is medium weight. The *context* is secondary. The user's eye lands on "2" first, then reads "of 5 sources" for context.

### 5.2 Card shadow — perceptible but not heavy

Current: `shadow(color: .black.opacity(0.06), radius: 2, y: 1)` — invisible on most displays.

**Change to**: `shadow(color: .black.opacity(0.08), radius: 3, y: 1)` — perceptible.

This is a tiny change but it moves the cards from "floating text" to "physical surface." The v2 guide says no glass on content cards, but a slightly stronger shadow is pure Apple (System Settings info cards use similar treatment).

---

## Phase 6: Motion and Accessibility Cleanup

### 6.1 Replace remaining bezier curves with springs

**File**: `Views/MainView.swift` (line 29)

Already changed to `.snappy` per codebase read. Verify no other `.easeInOut` or `.easeOut` calls remain:

```bash
grep -r "easeInOut\|easeOut\|easeIn\|linear" --include="*.swift" Views/
```

Replace any found with `.spring` or `.snappy` as appropriate.

### 6.2 Add Reduced Motion checks

Every view with custom animation should check:
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
// ...
.animation(reduceMotion ? .none : .snappy, value: state)
```

Priority files: `AgentPolicyCard`, `MainView`, `DomainsTableView`, `SourcesTableView`.

### 6.3 Accessibility labels on all custom controls

Audit every `Button` and `Toggle` that doesn't have an explicit `.accessibilityLabel()`. Priority:
- Agent Focus Control → add `.accessibilityHint("Filters table to show access for \(agent)")`
- Track Changes toolbar → add labels for each button
- Domain checkboxes → add `.accessibilityLabel("Allow \(domain) emails")`

### 6.4 Undo toast: add ⌘Z fallback

The undo toasts in `SourcesTableView` and `DomainsTableView` disappear after 5 seconds. Add `.onKeyPress("z", modifiers: .command)` as a non-time-limited undo path. Persist the last undoable action in the store even after the toast dismisses.

---

## Phase 7: Window Titling Consistency

**The problem from the review**: "Some screens foreground the app, some foreground the section, some foreground a back action."

**The rule**: The window title bar shows the *location*. The toolbar shows *actions and filters*.

| Screen | Current Title | Change To | Subtitle |
|--------|--------------|-----------|----------|
| Overview | "Overview" | "Manifold" | (none) |
| Files (no selection) | "Manifold" (from sidebar) | "Manifold" | "Files" |
| Files (source selected) | Source name | Source name | Item count |
| Recently Modified | "Recently Modified" | "Recently Modified" | "X of Y files across Z sources" |
| AI-Touched Files | "AI-Touched Files" | "AI-Touched Files" | "X of Y files..." |
| Emails - Domains | "Manifold" | "Manifold" | "Domains" |
| Emails - Messages | Account email | Account email | Message count |
| Settings | "AI Apps" / "Storage" etc. | Keep (system Settings pattern) | — |

The pattern: the app name appears when you're at a top-level tab. Section names appear as subtitles. Detail names replace the title when you've navigated into a specific item.

---

## Implementation Order (for Claude Code)

```
Phase 1  →  ~2 hours  →  AgentPolicyCard + OverviewView copy/state fixes
Phase 4.1 →  ~1 hour  →  Date formatter utility (unblocks Phase 4.2)
Phase 2.2 →  ~3 hours →  Files source deduplication (new FilesLandingView)
Phase 3  →  ~4 hours  →  Domains grouping, policy text, checkbox position, toolbar
Phase 2.1 →  ~2 hours →  Overview activity summary
Phase 4  →  ~2 hours  →  Formatting, truncation, density normalization
Phase 5  →  ~1 hour  →  Card visual hierarchy + shadow
Phase 6  →  ~2 hours →  Motion, a11y, undo
Phase 7  →  ~1 hour  →  Window titles
```

Total: ~18 hours of implementation work.

---

## What This Plan Does NOT Change

Per the v2 design guide constraints:

- No Liquid Glass on content surfaces
- No custom sheet presentation choreography
- No blanket backgroundExtensionEffect
- No custom segmented control highlight animations
- System transitions for all sheets and inspectors
- Existing navigation architecture (NavigationSplitView patterns) preserved
- No model/persistence layer changes except the activity summary computed property

Per the review's guidance:

- No badge color theory work
- No "app identity" branding work (clarity and trust come first)
- No Unicode arrow fix as a standalone task (folded into Phase 1.4)
- Codex gets equal structural treatment; the fix is differentiating configured vs. unconfigured states, not reducing Codex's prominence

---

## Verification Checklist

After each phase, answer these from the v2 guide:

1. Does it preserve the current information architecture? (Phase 2.2 changes the default Files content but keeps the sidebar → detail flow)
2. Does it use system controls? (Phase 1.1 switches to Toggle, Phase 3.4 uses segmented Picker)
3. Does it respect Reduced Motion? (Phase 6 adds checks)
4. Does it avoid new main-thread work? (Phase 2.1 activity summary should be computed off-main)
5. Does it keep glass on chrome, not content? (No glass changes in this plan)
6. Does it improve clarity, not just visual flourish? (Every change is trust/clarity motivated)
7. Does it work with keyboard and VoiceOver? (Phase 6.3 adds labels)
8. Does it hold up with more data? (Phase 3.2 grouping handles 100+ domains; Phase 2.2 handles 20+ sources)
