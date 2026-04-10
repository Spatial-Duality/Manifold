# Manifold Redesign Plan v5.2

> **Incorporates**: Both rounds of design critique, v5.1 plan, Amar's 10 corrections to v5.1, the v2 APPLE-DESIGN-EXCELLENCE-GUIDE constraints, and LAYOUT-SPEC-v4.1 as the authoritative spec.
>
> **Ground rules from v2 guide**: No custom glass on content. No sheet morphs. No `glassEffectID` for sheets. No blanket `backgroundExtensionEffect`. Use named spring presets directly. Keep system transitions for sheets/inspectors.
>
> **Ground rules from v4.1 spec**: Standing Access + Optional Tracked Work Blocks. All broadening through Review & Update Access sheet. Sensitivity in Domains toolbar (visible, not buried). Agent Focus with Claude | Codex | Compare. Overview is full-width, no sidebar. "Pause Access" is a direct action button, not a background toggle.
>
> **Priority order**: (1) Remove visual noise, (2) fix shell grammar, (3) fix state truthfulness, (4) verify Review sheet, (5) rebuild Emails architecture, (6) strengthen trust signaling, (7) fix inspectors and explanation layer, (8) redesign Settings, (9) formatting/a11y/motion cleanup, (10) window polish.
>
> **Scope**: SwiftUI changes only. No model/persistence layer changes unless stated.
>
> **The core diagnosis**: The app has the right backbone. What's missing is hierarchy, spatial discipline, state truthfulness, and the explanation layer. The gap is not conceptual — it's about finishing.

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

## Phase 1: Separate Global Chrome from Local Toolbars

**The most urgent shell problem.** The title bar is doing double duty as global navigation AND local task controls. That's why the app feels webby.

### The rule:

| Layer | Contents |
|-------|----------|
| **Title bar** | App name/section title, global tab picker (Overview/Files/Emails), compact connection indicator, search (⌘K) |
| **Local toolbar** | Agent Focus, Compare, Search [tab-specific], Add Folder, Sort, Sensitivity — these belong to the *tab*, not the *window* |
| **Sidebar** | Navigation only |
| **Content** | Data |
| **Inspector** | Explanation, detail, context |

### 1.0 Move local controls out of the title bar

**File**: `Views/MainView.swift` (toolbar section)

Currently the toolbar at `.primaryAction` holds connection indicators, and per-tab views push their own controls (Agent Focus, Search Sources, etc.) into the toolbar. All of these end up in one flat row.

**Change**: Keep only the tab picker and connection indicator in the global toolbar. Each tab view owns its own local toolbar *below* the title bar using `.toolbar` with content-area placements:

```swift
// MainView — global toolbar stays minimal
.toolbar {
    ToolbarItem(placement: .principal) {
        Picker("Tab", selection: $store.selectedTab) { ... }
            .pickerStyle(.segmented)
            .frame(width: 280)
    }
    
    ToolbarItemGroup(placement: .primaryAction) {
        // Search and connection indicator only
        Button { commands.isPresented.toggle() } label: {
            Image(systemName: "magnifyingglass")
        }
        .keyboardShortcut("k", modifiers: .command)
        
        if store.isConnected, let agent = store.connectedAgent {
            HStack(spacing: 4) {
                Circle().fill(agent.lowercased().contains("codex") ? Color.purple : Color.blue)
                    .frame(width: 8, height: 8)
                Text(agent.capitalized).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    
    // Track Changes stays at .secondaryAction (only when active)
    if let block = store.policy.activeWorkBlock {
        ToolbarItemGroup(placement: .secondaryAction) {
            TrackChangesToolbarContent(block: block, ...)
        }
    }
}
```

Then in `SourcesTableView`, `DomainsTableView`, `FilesView` — each view defines its own toolbar items for Agent Focus, search, sort, etc. These appear in the content area's toolbar, not the window title bar.

```swift
// SourcesTableView — local toolbar
.toolbar {
    ToolbarItem(placement: .automatic) {
        AgentFocusControl(selection: $agentFocus)
    }
    ToolbarItem(placement: .automatic) {
        TextField("Search sources", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
    }
    ToolbarItem(placement: .primaryAction) {
        Button("Add Folder…", systemImage: "folder.badge.plus") { ... }
    }
}
```

**The visual effect**: The title bar becomes clean and stable. Tab-specific controls appear below it in a secondary toolbar row. This immediately makes the app feel more like Finder/Xcode and less like a web app header.

### 1.1 Sensitivity stays visible in the Domains toolbar

Per v4.1 spec Q3 resolution: "The sidebar's job is pure navigation. The sensitivity dropdown governs data that appears in the Domains table, so it lives in the Domains toolbar, right next to the Agent Focus segmented control."

**Do NOT move Sensitivity into a filter popover or menu.** It is a first-order trust boundary that materially changes what the agent can see. It must remain visible at all times in the Domains toolbar:

```swift
// DomainsTableView — local toolbar
.toolbar {
    ToolbarItem(placement: .automatic) {
        AgentFocusControl(selection: $agentFocus)
    }
    ToolbarItem(placement: .automatic) {
        // Sensitivity — always visible, never buried
        Picker("Sensitivity", selection: $sensitivity) {
            ForEach(EmailSensitivityLevel.allCases) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 180)
    }
    ToolbarItem(placement: .automatic) {
        TextField("Search domains", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
    }
}
```

The fix for toolbar overload is Phase 1.0 (moving local controls out of the title bar), not hiding controls.

---

## Phase 2: Fix Overview State Truthfulness and CTA Wording

**The problem**: Both agent cards show "Resume Access" in the screenshot. This is either a state bug (both agents are paused and the UI doesn't distinguish) or a copy bug (the label doesn't reflect actual state). In a governance app, ambiguous access state is a trust defect.

### 2.1 Fix the access control — keep as button, add state chip

**File**: `Views/AgentPolicyCard.swift`

Per v4.1 spec: "Pause Access is the emergency control. Styled as text-only in the agent's color by default. On hover, turns red. On click, immediately suspends all access."

**Do NOT convert to a Toggle/switch.** Pause Access is an operational intervention, not a background preference. A toggle invites casual flipping. A button with visible state communicates consequence.

**Current code** (paraphrased):
```swift
Button(isPaused ? "Resume Access" : "Pause Access", role: isPaused ? nil : .destructive) {
    onPauseToggle()
}
.buttonStyle(.plain)
.font(.callout)
```

**Change to**:
```swift
// State chip in the card header — always visible
HStack(spacing: 6) {
    Circle().fill(agentColor).frame(width: 10, height: 10)
    Text(agentName).font(.headline)
    
    // State chip — the user always knows the current state
    Text(isPaused ? "Paused" : "Active")
        .font(.caption.weight(.medium))
        .foregroundStyle(isPaused ? .orange : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (isPaused ? Color.orange : agentColor).opacity(0.12),
            in: Capsule()
        )
    
    Spacer()
    
    // Pause/Resume as a real button with consequence
    Button(isPaused ? "Resume Access" : "Pause Access") {
        onPauseToggle()
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .tint(isPaused ? .green : .red)
    .accessibilityLabel(isPaused ? "Resume access for \(agentName)" : "Pause access for \(agentName)")
    .accessibilityHint(isPaused ? "Resumes \(agentName) file and email access" : "Immediately suspends all \(agentName) access")
}
```

**Why this instead of a Toggle**: The incentive of a switch is to flip it casually — like Wi-Fi. The incentive of a button with a state chip is to act deliberately after reading the current state. Pause Access is closer to pulling an emergency brake than to setting a preference. The state chip means the user never has to infer the current state from a verb.

**When paused, the entire card should feel different:**
```swift
.opacity(isPaused ? 0.7 : 1.0)
.overlay(alignment: .top) {
    if isPaused {
        RoundedRectangle(cornerRadius: Spacing.cornerLarge)
            .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
    }
}
```

### 2.2 Fix the "connected" / "disconnected" emphasis inversion

**File**: `Views/AgentPolicyCard.swift`

Current: "connected" gets a capsule pill background. "disconnected" gets bare tertiary text.

**Change to**:
```swift
if isConnected {
    // Happy state is quiet — just a secondary label
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

### 2.3 Fix "disconnected but configured" vs "disconnected and unconfigured"

**File**: `Views/AgentPolicyCard.swift`

Both states currently show the same card. They need different remedies.

```swift
if !isConnected {
    if isConfigured {
        // Configured but offline → verify connection
        Button("Verify Connection") {
            // Re-check health
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    } else {
        // Not configured → go to setup
        Button("Set Up") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .controlSize(.small)
        .buttonStyle(.borderedProminent)
    }
}
```

Add `isConfigured: Bool` to the card's parameters. This comes from `IntegrationHealthModel` — whether the agent's MCP config exists, regardless of current connection state.

### 2.4 Fix "No email access" passivity

**File**: `Views/AgentPolicyCard.swift`

Current: `Text("No email access").font(.callout).foregroundStyle(.tertiary)`

**Change to**:
```swift
if emailAccountCount > 0 {
    // existing code
} else {
    Button {
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

### 2.5 Fix "View Activity →" Unicode arrow

**File**: `Views/AgentPolicyCard.swift`

Change `"View Activity \u{2192}"` to:
```swift
Label("Activity", systemImage: "waveform.path")
    .font(.callout)
    .foregroundStyle(.secondary)
```

### 2.6 Fix Track Changes — give it real weight as a mode entry point

**File**: `Views/OverviewView.swift`

Current: `.controlSize(.large)` + `.buttonStyle(.plain)` + `.foregroundStyle(.secondary)` — conflicting signals.

**Change to**:
```swift
// Start Tracked Work Block as a first-class mode CTA
if store.isConnected && !store.sources.isEmpty && store.policy.activeWorkBlock == nil {
    VStack(spacing: Spacing.standard) {
        Button {
            reviewSheetChange = ReviewAccessChange(
                description: "Start tracking changes",
                kind: .startWorkBlock
            )
        } label: {
            Label("Start Tracked Work Block", systemImage: "timeline.selection")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        
        Text("Monitor and review all AI file access in real time")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.top, Spacing.section)
}
```

**Note**: The label is "Start Tracked Work Block", NOT "Start Tracked Session". The entire v4.1 model uses Work Block language. "Session" pulls the product backward.

### 2.7 Solve Overview dead space through compositional confidence, not dashboarding

**The v4.1 Overview is intentionally sparse**: two agent cards + Work Block CTA. The dead space problem is not solved by adding more information (a "Recent Activity" card would turn it into a dashboard). It's solved by making the existing elements carry more weight.

**Changes**:

1. **Widen the cards**: Change `maxWidth: 640` to allow more breathing room:
```swift
// Give cards more presence
.frame(maxWidth: 560)  // or remove maxWidth and let cards breathe
```

2. **More vertical rhythm inside cards**: Add spacing between the file summary, email summary, and actions:
```swift
VStack(alignment: .leading, spacing: Spacing.section) {
    // Header: agent + state chip + pause button
    headerRow
    
    Divider()
    
    // Summaries with more visual weight
    VStack(alignment: .leading, spacing: Spacing.tight) {
        fileSummaryRow
        emailSummaryRow
    }
    
    // One compact "last activity" line — NOT a full activity feed
    if let lastEvent = store.lastActivityForAgent(agent) {
        HStack(spacing: Spacing.tight) {
            Text("Last: \(lastEvent.summary)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(ManifoldDateFormatter.relative(lastEvent.date))
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
    }
    
    Divider()
    
    // Actions
    actionsRow
}
```

3. **Stronger type hierarchy on counts**:
```swift
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

The count is medium weight. The context is secondary. The user's eye lands on the number first.

4. **Card shadow — perceptible but not heavy**:

Current: `shadow(color: .black.opacity(0.06), radius: 2, y: 1)` — invisible.

Change to: `shadow(color: .black.opacity(0.08), radius: 3, y: 1)` — present.

This moves cards from "floating text" to "physical surface."

---

## Phase 3: Polish/Verify Review & Update Access Sheet

**Why this is earlier than in v5.1**: Because all broadening opens Review & Update Access, the sheet is one of the most critical surfaces in the app. It must be verified before wiring more broadening triggers.

### 3.0 Verify the sheet matches v4.1 spec

**File**: `Views/ReviewAccessSheet.swift`

The v4.1 spec defines the sheet precisely:
- Full-height attached sheet
- "Review & Update Access" title
- Agent switcher header: `[Claude ● | ○ Codex]`
- "What's Changing" section with green-tinted background
- Files | Emails internal tab bar
- Source/domain checklists with "(current)" and "(new ✦)" labels
- Sensitivity picker on Emails tab
- Advanced disclosure (collapsed)
- Sticky footer with counts + CTAs

**Verify each of these elements exists in the current implementation.** If any are missing, implement them. If the sheet is slow or cluttered, fix that — per v4.1: "The sheet MUST be fast and lightweight. If it's slow or cluttered, this design fails."

### 3.1 Verify primary button labels by context

Per v4.1 Copy Guide:
- First grant: "Allow Access"
- Updating existing: "Update Access"
- Starting work block: "Start Tracked Work Block"
- Copying from other agent: "Copy Access"

### 3.2 Verify the sheet pre-populates correctly

When opened from a specific trigger (e.g., checking a source checkbox), the "What's Changing" section must highlight that specific addition. The sheet should take under 2 seconds to review and confirm for a simple single-source addition.

---

## Phase 4: Rebuild Emails as One Stable Split-View

**File**: `Views/MainView.swift` (EmailsTab) + `Views/Email/EmailView.swift`

**The problem**: Domains and Messages are currently two separate screens with a text-button toggle. This breaks the stable sidebar model. The user experiences a structural jump between two different architectures.

**The fix**: One NavigationSplitView, always. The sidebar always shows accounts and a top-level "All Domains" entry (matching v4.1 spec's "All Mail"). Selecting "All Domains" / "All Mail" shows DomainsTableView in the content area. Selecting a mailbox shows the message list. This is exactly how Apple Mail works.

```swift
private struct EmailsTab: View {
    @Environment(ManifoldStore.self) var store
    @State private var emailSelection: EmailSidebarSelection? = .allDomains
    
    enum EmailSidebarSelection: Hashable {
        case allDomains
        case account(EmailAccountID)
        case mailbox(MailboxID)
    }
    
    var body: some View {
        NavigationSplitView {
            EmailSidebar(selection: $emailSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            switch emailSelection {
            case .allDomains, nil:
                DomainsTableView()
            case .account(let accountID):
                EmailMessageList(accountID: accountID)
            case .mailbox(let mailboxID):
                EmailMessageList(mailboxID: mailboxID)
            }
        } detail: {
            if case .mailbox = emailSelection {
                EmailReadingPane()
            } else if case .account = emailSelection {
                EmailReadingPane()
            } else {
                ContentUnavailableView("Select a domain or mailbox",
                    systemImage: "envelope.badge.shield.half.filled",
                    description: Text("Choose an item from the sidebar to view details"))
            }
        }
    }
}
```

**The sidebar structure** (matches v4.1 spec):
```
All Mail             ← default, shows DomainsTableView
─────────────
amar.gandhi@me.com
  ├ Inbox            [342]
  ├ Sent
  ├ Archive
  └ ...
─────────────
Smart Mailboxes
  ├ Has Attachments
  ├ Flagged
  └ [+]
─────────────
[+ Add Account…]
[View Activity →]
```

**What this changes**: No more "View Messages" / "← Domains" toggle. The sidebar IS the mode switch (per v4.1 spec rule). "All Mail" is the email governance view. Mailboxes are the email browsing view. Same window grammar throughout.

---

## Phase 5: Rework Domains Into a Governance Tool

**The problem**: A flat list of 50+ domains with unexplained "future" text, far-right checkboxes, no grouping, and no risk prioritization.

### 5.1 Replace "future" with human-readable policy text

**File**: `Views/Email/DomainsTableView.swift`

Per v4.1 spec: checked/active domains show "+ future" as inline text after the count. Unchecked domains show no future indicator. Hidden domains show "—".

```swift
// Checked domain
Text("\(domain.emailCount) emails · + future mail")
    .font(.caption)
    .foregroundStyle(.secondary)

// Unchecked domain
Text("\(domain.emailCount) emails")
    .font(.caption)
    .foregroundStyle(.secondary)

// Hidden by sensitivity
Text("\(domain.emailCount) emails · —")
    .font(.caption)
    .foregroundStyle(.tertiary)
```

### 5.2 Add section grouping — use stored metadata, not heuristics

Per v4.1 spec, domains are grouped by category: **Work, Automated, Personal, Hidden by sensitivity**. These are the four sections.

**Do NOT use ad-hoc domain-string matching** (e.g., guessing "hsbc" = financial). In a trust product, false confidence is dangerous. Use only categories backed by:
- Explicit user assignment (if available)
- `EmailSensitivityFilter` rules (which already classify 2FA, banking, health)
- A neutral fallback for everything else

```swift
enum DomainCategory: String, CaseIterable {
    case work = "Work"
    case automated = "Automated"
    case personal = "Personal"
    case hiddenBySensitivity = "Hidden by Sensitivity"
}
```

If the category system eventually needs heuristics (e.g., guessing gmail.com = Personal), those should be:
- Treated as suggestions the user can override
- Never shown as certain
- Gated behind a user-facing label like "Suggested: Personal"

For now, use the v4.1 structure and let uncategorized domains fall into a neutral group.

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

### 5.3 Keep access columns stable — do not move checkboxes

Per v4.1 spec, the table grammar is: `Name | Category | Emails | + Future | Access` (single agent) or `Name | Category | Emails | + Future | Claude | Codex` (Compare mode).

**Do NOT move the access checkbox to the first column.** The v4.1 Files and Emails model is built around Agent Focus and Compare. The access column lives in a stable trailing position. Moving it between Files and Emails creates inconsistency.

The way to make access more visible at row level is:
- Row tinting (Phase 6)
- Hidden-by-sensitivity sections with reason badges (Phase 6)
- Clear column headers
- `+ future mail` inline text

Not by changing the table grammar.

---

## Phase 6: Row-Level Trust Signaling

**The review's core demand**: "Access should live where the data lives."

### 6.1 Files: Subtle row tinting for granted sources

**File**: `Views/SourcesTableView.swift`

Per v4.1 spec: "When a source is checked for the focused agent, the row gets a subtle background tint in the agent's color (very light blue for Claude, very light purple for Codex). Unchecked rows have no tint."

```swift
.listRowBackground(
    source.isGrantedToFocusedAgent
        ? agentColor.opacity(0.04)
        : Color.clear
)
```

4% opacity — barely visible, but enough that when scanning a list of 20 sources, the granted ones form a visible band.

### 6.2 Domains: Show hidden sections with reasons

Per v4.1 spec: hidden domains show disabled checkboxes (not emoji), reduced weight text, and a Note column with the reason (banking, health, 2FA).

```swift
// Hidden by sensitivity section
Section("Hidden by Sensitivity") {
    ForEach(hiddenDomains) { domain in
        HStack {
            Toggle("", isOn: .constant(false))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(true)
            
            Text("@\(domain.name)")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(domain.emailCount, format: .number)
                .font(.callout)
                .foregroundStyle(.tertiary)
            
            // Reason badge
            Text(domain.hiddenReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.08), in: Capsule())
        }
    }
}
```

### 6.3 Messages: Show why a message is visible

In `EmailMessageRow`, add trust indicators per v4.1 spec:

```swift
if message.visibilityReason == .temporaryReveal {
    Text("Revealed temporarily")
        .font(.caption2)
        .foregroundStyle(.orange)
} else if message.isHiddenBySensitivity {
    HStack(spacing: 4) {
        Text("Hidden")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        Text(message.hiddenReason)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.06), in: Capsule())
    }
}
// Default visible-by-domain-grant: no indicator needed
```

---

## Phase 7: Fix Inspectors and the Explanation Layer

**Why this is earlier than in v5.1**: The inspector is where Manifold explains trust decisions. It's not polish — it's meaning.

### 7.1 File Inspector — explain access inheritance

Per v4.1 spec, the file inspector shows:
```
ACCESS
  Accessible because web-app is shared with Claude.
  [also shared with Codex]
```

**File**: `Views/Versions/VersionDetailView.swift` (or the inspector wrapper)

Verify this access explanation block exists. If it doesn't, add it:

```swift
// Access explanation section
Section("Access") {
    if let source = store.sourceContaining(filePath) {
        let agents = store.agentsWithAccessTo(source)
        if agents.isEmpty {
            Text("Not accessible to any agent")
                .font(.callout)
                .foregroundStyle(.tertiary)
        } else {
            ForEach(agents) { agent in
                HStack(spacing: 6) {
                    Circle().fill(agent.color).frame(width: 8, height: 8)
                    Text("Accessible because \(source.displayName) is shared with \(agent.displayName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### 7.2 Domain Inspector — explain why a domain is hidden

When a domain row is clicked, the inspector should explain:
- If hidden by sensitivity: which rule triggered it (banking, health, 2FA), and what the user can do about it (loosen sensitivity, but warn about consequences)
- If unchecked: that the user can check it (broadening → opens Review sheet)
- If checked: a summary of what the agent can see (email count, future mail status)

```swift
Section("Access Policy") {
    if domain.isHiddenBySensitivity {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Label("Hidden by \(domain.hiddenReason) filter", systemImage: "eye.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("This domain is blocked by the \(sensitivity.displayName) sensitivity level. To make these emails visible, change sensitivity to a less restrictive level.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    } else if domain.isGranted {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Label("Visible to \(focusedAgent.displayName)", systemImage: "eye")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("\(domain.emailCount) emails + future mail")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
```

### 7.3 Activity in Inspector context

Per v4.1 spec: the inspector can show file-specific activity. When viewing a file's inspector, the activity section shows events for that specific file.

Verify `VersionDetailView` includes a file-scoped activity section, not just the global Activity drawer.

---

## Phase 8: Redesign Settings AI Apps and Mail as Product Panes

### 8.1 Settings AI Apps — integration cards with headline state

**File**: `Views/Settings/AIAppsSettingsPane.swift`

Current checklist format feels like QA output, not a product surface.

```swift
// Claude integration card
VStack(alignment: .leading, spacing: Spacing.section) {
    HStack {
        Circle().fill(.blue).frame(width: 10, height: 10)
        Text("Claude").font(.title3.weight(.medium))
        Spacer()
        // Headline state chip
        Text("Connected")
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.green.opacity(0.12), in: Capsule())
    }
    
    // Health checks — compact, not the headline
    VStack(alignment: .leading, spacing: 6) {
        checkRow("App installed", status: .ok)
        checkRow("MCP configured", status: .ok)
        checkRow("Connection verified", status: .ok)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    
    Button("Reconnect") { ... }
        .buttonStyle(.bordered)
        .controlSize(.small)
}
.padding(Spacing.edge)
.background(.background, in: RoundedRectangle(cornerRadius: Spacing.cornerMedium))
.overlay {
    RoundedRectangle(cornerRadius: Spacing.cornerMedium)
        .strokeBorder(.separator, lineWidth: 0.5)
}
```

**For Codex when not configured**: Headline chip says "Needs Setup" in orange. Primary action is "Set Up Codex" as `.borderedProminent`. Health checks show pending states. Use a `DisclosureGroup` when not configured:

```swift
if codexConfigured {
    codexSection  // Full card
} else {
    DisclosureGroup("Codex") {
        codexSection
    }
    .foregroundStyle(.secondary)
}
```

### 8.2 Storage pane — proportional bar

```swift
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

### 8.3 Mail Settings — account rows with status

Show each account as a row with provider icon, status, last sync time, and enabled toggle. Move technical paths (SMTP config, etc.) into a disclosure group.

---

## Phase 9: Formatting, Accessibility, Motion, and Truncation Cleanup

### 9.1 Date formatting — context-appropriate, not identical everywhere

Create one shared utility but use context-appropriate output:

```swift
struct ManifoldDateFormatter {
    /// For summaries, activity, toasts — relative time
    static func relative(_ date: Date) -> String {
        let now = Date()
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else if now.timeIntervalSince(date) < 7 * 86400 {
            return date.formatted(.relative(presentation: .named))
        } else if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
    
    /// For dense file lists, email tables, version rows — short absolute
    static func compact(_ date: Date) -> String {
        let now = Date()
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        } else if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))
        }
    }
}
```

Use `relative()` for: Overview summaries, Activity drawer, toasts, recent events, "last activity" lines.
Use `compact()` for: file tables, email tables, version history rows, sidebar counts.

### 9.2 Fix email message row dates

**File**: `Views/Email/EmailMessageRow.swift`

Ensure all paths through the ISO8601 parsing use the correct formatter. No raw timezone strings should leak through.

### 9.3 Fix sidebar truncation

**File**: `Views/MainView.swift`

Change sidebar minimum width:
```swift
.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
```

### 9.4 Agent Focus label: rename "Cowork"

**File**: `Views/Helpers/AgentFocusControl.swift`

"Cowork" → "All" (if it means all agents combined) or remove it if default is "all agents."

The picker should read: `All | Claude | Codex | Compare`

### 9.5 Replace remaining bezier curves with springs

```bash
grep -r "easeInOut\|easeOut\|easeIn\|linear" --include="*.swift" Views/
```

Replace any found with `.spring` or `.snappy` as appropriate.

### 9.6 Add Reduced Motion checks

Every view with custom animation:
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
// ...
.animation(reduceMotion ? .none : .snappy, value: state)
```

Priority files: `AgentPolicyCard`, `MainView`, `DomainsTableView`, `SourcesTableView`.

### 9.7 Accessibility labels on all custom controls

Audit every `Button` and `Toggle` without an explicit `.accessibilityLabel()`:
- Agent Focus Control → `.accessibilityHint("Filters table to show access for \(agent)")`
- Track Changes toolbar → labels for each button
- Domain checkboxes → `.accessibilityLabel("Allow \(domain) emails")`

### 9.8 Undo toast: add ⌘Z fallback

The undo toasts in `SourcesTableView` and `DomainsTableView` disappear after 5 seconds. Add `.onKeyPress("z", modifiers: .command)` as a non-time-limited undo path. Persist the last undoable action in the store even after the toast dismisses.

### 9.9 AI-Touched Files: Fix filter bar position

**File**: `Views/FilesView.swift`

The filter bar and search must be pinned to the top of the content area, above the list/empty state. Ensure the filter controls are in the toolbar or pinned section header, not embedded in scrollable content.

---

## Phase 10: Window Title and Polish

**Low ROI but not wrong.** Do this last.

### The rule

The window title bar shows the *location*. The toolbar shows *actions and filters*.

| Screen | Title | Subtitle |
|--------|-------|----------|
| Overview | "Manifold" | (none) |
| Files (no selection) | "Manifold" | "Files" |
| Files (source selected) | Source name | Item count |
| Recently Modified | "Recently Modified" | File count |
| AI-Touched Files | "AI-Touched Files" | File count |
| Emails - Domains | "Manifold" | "Domains" |
| Emails - Messages | Account email | Message count |
| Settings | Pane name | Keep system pattern |

---

## Files Source Deduplication (embedded in Phase 1)

**The problem**: Sources appear in the sidebar AND as the default content table. The user sees the same items twice.

**The fix (per Amar's correction)**: Keep the All Sources access table as the default Files surface. It IS the product surface. Fix the duplication by making the sidebar clearly navigation and the table clearly ownership:

1. **Keep All Sources selected by default** in the sidebar
2. **Keep the center source access table** as the main content (SourcesTableView with Name, Path, Items, Size, Access columns, footer totals)
3. **Clean up the sidebar** so it reads as navigation, not a second copy:
   - Sidebar source rows are compact: icon + name + agent-colored dot
   - Sidebar does NOT show path, items, size, or access checkboxes
   - The visual distinction is clear: sidebar = navigation index, content = ownership surface
4. **Make the table stronger** through row tinting (Phase 6), footer totals, and less dead space

---

## Implementation Order (for Claude Code)

```
Phase 0    →  30 min   →  Remove fake row strips
Phase 1    →  3 hours  →  Separate global chrome from local toolbars
Phase 2    →  3 hours  →  Fix Overview state truthfulness, CTA wording, card composition
Phase 3    →  2 hours  →  Polish/verify Review & Update Access sheet
Phase 4    →  4 hours  →  Rebuild Emails as one stable split-view
Phase 5    →  2 hours  →  Domains: grouping, "future" text, stable access columns
Phase 6    →  2 hours  →  Row-level trust signaling (tints, hidden sections, reasons)
Phase 7    →  2 hours  →  Fix inspectors and explanation layer
Phase 8    →  2 hours  →  Redesign Settings AI Apps + Mail + Storage
Phase 9    →  3 hours  →  Formatting, a11y, motion, truncation, ⌘Z undo
Phase 10   →  1 hour   →  Window title consistency
```

Total: ~24.5 hours of implementation work.

**Critical path**: Phases 0 → 1 → 2 → 3 → 4 are structural. Everything after is polish on a correct shell. Do not start Phase 6 (trust signaling) until Phase 1 (toolbar separation) is done — the controls need to be in the right place before you tune their styling.

---

## What This Plan Does NOT Do

Per the v2 design guide constraints:
- No Liquid Glass on content surfaces
- No custom sheet presentation choreography
- No blanket backgroundExtensionEffect
- No custom segmented control highlight animations
- System transitions for all sheets and inspectors

Per v4.1 spec alignment:
- No Toggle/switch for Pause Access (kept as button with state chip)
- No "session" language anywhere (all Work Block language)
- No demotion of the Sources access table (kept as the default Files surface)
- No hiding Sensitivity in a filter menu (kept visible in Domains toolbar)
- No dashboard-style activity card on Overview (solved dead space through composition)
- No moving access checkboxes to the first column (stable trailing column position)
- No ad-hoc domain categorization heuristics as core truth (metadata-backed only)

Per the review's guidance:
- No badge color theory work
- No "app identity" branding work (clarity and trust come first)
- Codex gets equal structural treatment; the fix is differentiating configured vs. unconfigured states

---

## Verification Checklist

After each phase, answer these from the v2 guide + v4.1 spec:

1. Does it preserve the v4.1 information architecture?
2. Does it use system controls?
3. Does it respect Reduced Motion?
4. Does it avoid new main-thread work?
5. Does it keep glass on chrome, not content?
6. Does it improve clarity, not just visual flourish?
7. Does it work with keyboard and VoiceOver?
8. Does it hold up with more data?
9. Does it maintain the v4.1 copy/label guide? (No session language, no retired terms)
10. Does Pause Access still feel like an intervention, not a preference?
11. Is Sensitivity visible, not buried?
12. Does every broadening still go through the Review sheet?
