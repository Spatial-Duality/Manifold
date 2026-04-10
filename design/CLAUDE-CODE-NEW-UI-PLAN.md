# Manifold v4.1 — New UI Implementation Plan (Design-Review-Corrected)

> **What this is**: The operative build plan for all new UI work — Settings, Setup Assistant, connection sheets, health model — plus targeted fixes to existing views that the Apple-quality design review flagged. Every change in `DESIGN-REVIEW-APPLE-QUALITY.md` is addressed here. Following this plan should raise the design score from 3.8 to 4.5+.
>
> **Supersedes**: `CLAUDE-CODE-SETTINGS-SETUP-PLAN.md` (phases 11–14). That document is now historical. This plan re-numbers phases and incorporates every review critique.
>
> **Required skill**: Invoke `swiftui-pro` before writing any SwiftUI view code.
>
> **Source of truth**: `design/LAYOUT-SPEC-v4.md` for the product model. This document for build specifics. Where this document contradicts LAYOUT-SPEC, **this document wins** — the review caught things LAYOUT-SPEC got wrong.

---

## Design Review Fixes — Complete Tracklist

Every critique from the review is mapped to a phase below. Nothing is ignored. Where I disagree with the review, I say so and explain why.

| Review Critique | Fix | Phase |
|----------------|-----|-------|
| **Top 5 — Inline checks in Setup Assistant** (no nested sheets) | Setup Assistant Screen 2 shows LiveCheckRow inline, no `.sheet()` | Phase D |
| **Top 5 — Rename "Start Tracked Work Block"** | → "Track Changes" everywhere: button labels, banner, Review sheet, keyboard shortcuts | Phase A |
| **Top 5 — Work block banner → toolbar modification** | Banner becomes toolbar items with tinted bar background, not a separate VStack strip | Phase A |
| **Top 5 — Debounce IntegrationHealthModel** | 5-second `lastChecked` cache, force-refresh only on explicit action | Phase B |
| **Top 5 — Shorten button labels** | "Update Access…" on cards, "Review & Update Access" as sheet title, "Review Access…" in menu | Phase A |
| Card left-border is non-Apple | Current code already uses shadow + stroke (not left border). No change needed. ✅ Already correct. | — |
| "Pause Access" hover-to-red is web design | Use `Button(role: .destructive)` — always red. Remove `@State pauseHovered` hover logic. | Phase A |
| Top bar glass: tabs must be in `.toolbar {}` | Current `MainView.swift` already uses `.toolbar { ToolbarItem(placement: .principal) }`. ✅ Already correct. | — |
| Activity Drawer + Inspector should be independent | Allow both open simultaneously on wide displays (≥1280pt). Below that, mutually exclusive. | Phase A |
| Settings window too small (520×460) | Use SwiftUI `Settings {}` scene with no fixed frame — auto-sizes per pane. Floor at 580×500. | Phase C |
| Component version info missing from Settings | Add `"Manifold v\(version) · MCP v\(mcpVersion)"` line in Storage pane footer. | Phase C |
| Setup Assistant "Get Started" → "Continue" | Change button label. | Phase D |
| Setup Assistant "Open Manifold" → "Done" | Change button label. | Phase D |
| Setup Assistant per-checkbox sheet fatigue during initial setup | Screen 3 uses `NSOpenPanel` multi-select, single review. Not per-checkbox. | Phase D |
| Connection sheet 3 footer buttons → 2 | Remove "Check Again" from footer. Add inline ↻ refresh per failed check row. | Phase E |
| Connection sheet size inconsistency (460×420 vs 460×380) | Both sheets → 460×420. | Phase E |
| Claude install opens Finder (.mcpb) as primary | ConfigWriter is primary (silent). `.mcpb` mention moves to disclosure group. | Phase E |
| AgentFocusControl needs `.accessibilityHint()` | Add hint: "Shows [agent] access columns in the table" | Phase A |
| Undo toast too fast for VoiceOver | Persist toast if VoiceOver running (`UIAccessibility.isVoiceOverRunning` equivalent). Add ⌘Z fallback. | Phase A |
| DomainModel: no pagination, no off-main-actor computation | Compute domains on background actor. Lazy load with `List` virtualization for 100+ domains. | Phase A |

---

## Phase A: Design Polish — Fixes to Existing Views

**Goal**: Apply every review fix that touches existing files. Zero new files created. After this phase, the existing app is closer to native quality.

### A.1: Rename "Tracked Work Block" → "Track Changes"

Global find-and-replace across the codebase. This is a naming change, not a behavioral change.

**Files to modify**:
- `Views/OverviewView.swift` — button label: `"Start Tracked Work Block"` → `"Track Changes"`
- `Views/WorkBlockBannerView.swift` — banner text: `"Work Block"` → `"Tracking Changes"`, button: `"Finish & Review"` → `"Review Changes"`, doc comments
- `Views/ReviewAccessSheet.swift` — CTA variant: `"Start Tracked Work Block"` → `"Track Changes"`
- `ManifoldApp.swift` — keyboard shortcut menu label: `"Toggle Work Block"` → `"Track Changes"` (⌘⇧W)
- `LAYOUT-SPEC-v4.md` — update all references (spec follows code, not the other way around here)

```swift
// OverviewView.swift — line 24 area
Label("Track Changes", systemImage: "timeline.selection")

// WorkBlockBannerView.swift — line 39
Text("Tracking Changes")
    .font(.callout.weight(.medium))

// WorkBlockBannerView.swift — line 83
Button("Review Changes", action: onFinish)
```

**Rationale**: "Track Changes" is universally understood (Word, Pages, Git). "Work Block" is internal jargon that requires explanation. A user who has never read documentation should understand what the button does from its label alone.

### A.2: Shorten Button Labels

Three forms for three contexts. All shorter than the current single label.

| Context | Old | New |
|---------|-----|-----|
| Agent card button | "Review & Update Access" | "Update Access…" |
| Sheet title | "Review & Update Access" | "Review & Update Access" (unchanged) |
| Menu bar command (⌘⇧R) | "Review & Update Access" | "Review Access…" |

**Files to modify**:
- `Views/AgentPolicyCard.swift` line 60: `"Review & Update Access"` → `"Update Access…"`
- `Views/ReviewAccessSheet.swift` header: keep "Review & Update Access"
- `ManifoldApp.swift` menu command: `"Review Access…"`

```swift
// AgentPolicyCard.swift
Button("Update Access…", action: onReviewAccess)
    .controlSize(.regular)
```

The ellipsis (…) is Apple convention for "this opens a modal." It tells the user something will appear before any action is taken. The button is now 2 words instead of 4.

### A.3: Fix "Pause Access" Button — Use Destructive Role

Remove the hover-to-red pattern. Use `Button(role:)` which makes it red by default on macOS.

**File**: `Views/AgentPolicyCard.swift`

```swift
// REMOVE the @State private var pauseHovered = false
// REMOVE the .onHover { pauseHovered = $0 }
// REMOVE the pauseButtonColor computed property

// REPLACE the pause button with:
Button(isPaused ? "Resume Access" : "Pause Access", role: isPaused ? nil : .destructive) {
    onPauseToggle()
}
.buttonStyle(.plain)
.font(.callout)
```

When `role: .destructive`, SwiftUI renders the text in red by default — no hover state needed. "Resume Access" has no destructive role, so it renders in the standard tint. This is exactly how Apple's own buttons work in System Settings.

### A.4: Move Work Block Banner into Toolbar

The current banner is a VStack child between the toolbar and tab content. The review correctly identified this as non-Apple — it breaks the glass-to-content visual flow.

**New approach**: When a work block is active, the toolbar itself changes:
1. A colored background tint (agent color at 8% opacity) covers the toolbar
2. The banner info + buttons move into `ToolbarItemGroup(placement: .secondaryAction)` on the trailing side
3. The tab segmented control remains in `.principal`

**File**: `Views/MainView.swift`

```swift
// REMOVE the VStack banner child:
// if let block = store.policy.activeWorkBlock {
//     WorkBlockBannerView(...)
// }

// ADD to the existing .toolbar { } block:
ToolbarItemGroup(placement: .secondaryAction) {
    if let block = store.policy.activeWorkBlock {
        TrackChangesToolbarContent(
            block: block,
            onFinish: { Task { await store.policy.finishWorkBlock() } },
            onPause: { Task { await store.policy.pauseWorkBlock() } },
            onStop: { Task { await store.policy.stopWorkBlock() } }
        )
    }
}

// The toolbar gets a background tint when active:
.toolbarBackground(
    store.policy.activeWorkBlock != nil
        ? (store.policy.activeWorkBlock?.agent == .codex ? Color.purple : Color.blue).opacity(0.08)
        : Color.clear,
    for: .windowToolbar
)
```

**New file**: `Components/TrackChangesToolbarContent.swift` — Extracted from `WorkBlockBannerView` but as a horizontal toolbar layout, not a full-width strip. Shows: agent dot + "Tracking" + elapsed time + [Review Changes] [Pause] [Stop ✕].

```swift
struct TrackChangesToolbarContent: View {
    let block: WorkBlockRecord
    let onFinish: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    @State private var showStopConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(block.agent == .codex ? Color.purple : Color.blue)
                .frame(width: 6, height: 6)

            Text("Tracking")
                .font(.caption.weight(.medium))

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(elapsedText(at: context.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button("Review Changes", action: onFinish)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(block.agent == .codex ? .purple : .blue)

            Button(block.isPaused ? "Resume" : "Pause", action: onPause)
                .controlSize(.small)

            Button("Stop", role: .destructive) { showStopConfirmation = true }
                .controlSize(.small)
        }
        .confirmationDialog("Stop tracking changes?", isPresented: $showStopConfirmation) {
            Button("Discard Changes", role: .destructive, action: onStop)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All changes since baseline will be discarded.")
        }
    }
}
```

**Keep `WorkBlockBannerView.swift`** as a fallback for when toolbar space is too tight (e.g., if we later support a compact window mode), but MainView no longer renders it.

### A.5: Activity Drawer + Inspector Independence

The review flagged that these are mutually exclusive. On wide displays (≥1280pt) they should be independent panels.

**File**: `Views/MainView.swift` (or wherever the inspector/drawer are wired)

```swift
// Instead of replacing inspector with drawer:
.inspector(isPresented: inspectorBinding) {
    FileInspectorView()
}
// Activity drawer uses a separate trailing panel or sheet
// On wide displays (GeometryReader), show both
// On narrow displays, Activity replaces Inspector (current behavior)

@Environment(\.horizontalSizeClass) var sizeClass

// Simple heuristic:
GeometryReader { geo in
    if geo.size.width >= 1280 {
        // Both panels available simultaneously
        HStack(spacing: 0) {
            tabContent
            if store.showInspector { FileInspectorView().frame(width: 300) }
            if store.showActivityDrawer { ActivityDrawerView().frame(width: 300) }
        }
    } else {
        // Mutually exclusive (current behavior)
        tabContent
            .inspector(isPresented: inspectorOrDrawerBinding) { ... }
    }
}
```

This is how Xcode does it — navigator, editor, inspector, and debug area are all independent, but on a small screen the debug area overlaps.

### A.6: AgentFocusControl Accessibility Hint

**File**: `Components/AgentFocusControl.swift` (or wherever the segmented control lives)

```swift
Picker("Agent", selection: $mode) {
    Text("Claude").tag(AgentFocusMode.claude)
    Text("Codex").tag(AgentFocusMode.codex)
    Text("Compare").tag(AgentFocusMode.compare)
}
.pickerStyle(.segmented)
.frame(width: 220)
.accessibilityHint("Switches the table to show access for \(mode.displayName)")
```

### A.7: Undo Toast VoiceOver Persistence + ⌘Z

The undo toast currently auto-dismisses after ~5 seconds. VoiceOver users may not reach it in time.

```swift
// In the undo toast view or model:
import Accessibility

func showUndoToast(_ message: String, undo: @escaping () -> Void) {
    // Set the undo action for ⌘Z
    currentUndoAction = undo

    // Show toast
    toastMessage = message
    showToast = true

    // Auto-dismiss — but only if VoiceOver is NOT running
    if !AccessibilityNotification.isVoiceOverRunning {
        Task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { showToast = false }
        }
    }
    // If VoiceOver IS running, toast stays until manually dismissed or ⌘Z is pressed
}

// Wire ⌘Z in MainView or ManifoldApp:
.onKeyPress("z", modifiers: .command) {
    if let undo = store.currentUndoAction {
        undo()
        store.currentUndoAction = nil
        store.showToast = false
        return .handled
    }
    return .ignored
}
```

**Note**: On macOS, the equivalent of `UIAccessibility.isVoiceOverRunning` is checking `NSWorkspace.shared.isVoiceOverEnabled` or using the `AXIsProcessTrusted()` + `AXUIElementIsAttributeSettable` APIs. The `swiftui-pro` skill should have the correct macOS 26 pattern.

### A.8: DomainModel Off-Main-Actor + Lazy Loading

The review flagged that domain aggregation could be slow for large mailboxes.

```swift
// Models/DomainModel.swift
@Observable
@MainActor
class DomainModel {
    var domains: [DomainAggregate] = []
    var isLoading = false

    func computeDomains(from emailStore: EmailStore) async {
        isLoading = true
        // Do the heavy work off the main actor
        let result = await Task.detached(priority: .userInitiated) {
            // emailStore is an actor, so this is safe
            let allDomains = try? await emailStore.allDomainAggregates()
            return allDomains ?? []
        }.value
        domains = result
        isLoading = false
    }
}
```

For the Domains table view, use SwiftUI `List` (which virtualizes by default) rather than `ForEach` inside `ScrollView` (which doesn't). For 100+ domains, add a `.searchable()` modifier to let users filter rather than scroll.

### Validation — Phase A
- "Track Changes" label everywhere. Zero mentions of "Work Block" in UI-facing strings.
- Agent card button says "Update Access…" (with ellipsis).
- "Pause Access" button is red by default (no hover effect).
- Work block indicator lives in the toolbar, not as a separate banner strip.
- ⌘Z undoes the most recent narrowing action. VoiceOver toast persists.
- AgentFocusControl has an accessibility hint.
- DomainModel computes off main actor.

---

## Phase B: IntegrationHealthModel — With Debouncing

**Goal**: Replace flat booleans in SetupModel with structured, pollable, debounced health state. No UI yet.

### B.1: Create `Models/AgentConnectionState.swift`

Identical to the prior plan — Claude has 3 checks, Codex has 2. No "signed in" check for Codex (auth is in Keychain, inaccessible).

```swift
import Foundation

public enum AgentConnectionStatus: String, Sendable {
    case unknown, checking, notInstalled, installed, configured, connected, error
}

@Observable
@MainActor
public final class AgentConnectionState: Identifiable {
    public let id: TargetApp

    // Claude (3 checks)
    var appInstalled: AgentConnectionStatus = .unknown
    var mcpConfigured: AgentConnectionStatus = .unknown
    var connectionVerified: AgentConnectionStatus = .unknown

    // Codex (2 checks)
    var cliInstalled: AgentConnectionStatus = .unknown
    var mcpAdded: AgentConnectionStatus = .unknown

    var errorDetail: String?

    var overallStatus: AgentConnectionStatus {
        switch id {
        case .cowork:
            if connectionVerified == .connected { return .connected }
            if [appInstalled, mcpConfigured, connectionVerified].contains(.error) { return .error }
            if appInstalled == .notInstalled { return .notInstalled }
            if mcpConfigured == .installed { return .configured }
            return .notInstalled
        case .codex:
            if mcpAdded == .installed { return .configured }
            if [cliInstalled, mcpAdded].contains(.error) { return .error }
            if cliInstalled == .notInstalled { return .notInstalled }
            return .notInstalled
        }
    }

    var checkCount: Int { id == .cowork ? 3 : 2 }

    init(agent: TargetApp) { self.id = agent }
}
```

### B.2: Create `Models/IntegrationHealthModel.swift` — With 5-Second Debounce

The review's performance critique: redundant filesystem reads on rapid Settings tab switches. Fix: time-based cache.

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "health")

@Observable
@MainActor
final class IntegrationHealthModel {
    var claude = AgentConnectionState(agent: .cowork)
    var codex = AgentConnectionState(agent: .codex)

    weak var store: ManifoldStore?

    // MARK: - Debounce (review fix: Performance §10)
    private var lastCheckedAt: Date?
    private static let cacheInterval: TimeInterval = 5.0

    /// Call this from Settings pane loads, sheet appears, etc.
    /// Returns cached results if called within 5 seconds of the last check.
    /// Pass `force: true` for explicit user-initiated "Check Again."
    func checkAll(force: Bool = false) async {
        if !force, let last = lastCheckedAt,
           Date().timeIntervalSince(last) < Self.cacheInterval {
            logger.debug("Health check skipped — cached result is \(Date().timeIntervalSince(last), format: .fixed(precision: 1))s old")
            return
        }
        lastCheckedAt = Date()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkClaude() }
            group.addTask { await self.checkCodex() }
        }
    }

    func state(for agent: TargetApp) -> AgentConnectionState {
        switch agent {
        case .cowork: return claude
        case .codex: return codex
        }
    }

    // MARK: - Claude checks

    func checkClaude() async {
        claude.appInstalled = .checking
        claude.mcpConfigured = .checking
        claude.connectionVerified = .checking

        // 1. Claude Desktop.app installed?
        let claudeAppPath = "/Applications/Claude.app"
        let altPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude.app").path
        claude.appInstalled = FileManager.default.fileExists(atPath: claudeAppPath)
            || FileManager.default.fileExists(atPath: altPath)
            ? .installed : .notInstalled

        // 2. Manifold MCP configured? (covers both ConfigWriter and .mcpb paths)
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = json["mcpServers"] as? [String: Any],
           servers.keys.contains(where: { $0.lowercased().contains("manifold") }) {
            claude.mcpConfigured = .installed
        } else {
            claude.mcpConfigured = .notInstalled
        }

        // 3. Live connection? (reads existing ManifoldStore infrastructure)
        if let store, store.isConnected,
           store.connectedAgent == "Claude" || store.connectedAgent == "cowork" {
            claude.connectionVerified = .connected
        } else if claude.mcpConfigured == .installed {
            claude.connectionVerified = .configured
        } else {
            claude.connectionVerified = .notInstalled
        }
    }

    // MARK: - Codex checks

    func checkCodex() async {
        codex.cliInstalled = .checking
        codex.mcpAdded = .checking

        // 1. Codex CLI installed?
        let paths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex",
                     FileManager.default.homeDirectoryForCurrentUser
                         .appendingPathComponent(".local/bin/codex").path]
        let found = paths.contains { FileManager.default.fileExists(atPath: $0) }
        codex.cliInstalled = found ? .installed : .notInstalled

        guard found else {
            codex.mcpAdded = .notInstalled
            return
        }

        // 2. Manifold in config.toml?
        let tomlPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
        if let contents = try? String(contentsOfFile: tomlPath, encoding: .utf8),
           contents.contains("[mcp_servers.manifold]") || contents.contains("mcp_servers.manifold") {
            codex.mcpAdded = .installed
        } else {
            codex.mcpAdded = .notInstalled
        }
    }
}
```

### B.3: Wire into ManifoldStore

```swift
// ManifoldStore.swift — add property:
let integrationHealth = IntegrationHealthModel()

// In init():
integrationHealth.store = self

// Compatibility shims for old code:
var mcpInstalled: Bool { integrationHealth.claude.mcpConfigured == .installed }
var claudeDesktopConfigured: Bool { integrationHealth.claude.mcpConfigured == .installed }
var codexConfigured: Bool { integrationHealth.codex.mcpAdded == .installed }
```

### B.4: Slim SetupModel

Keep only: `hasCompletedOnboarding`, `launchAtLogin`, `notifyOnSessionEnd`, `notifyOnAccessDenied`, `sessionNotesMode`.

Remove: `mcpInstalled`, `installError`, `claudeDesktopConfigured`, `codexConfigured`, `checkMCPInstalled()`, `checkAgentConfigs()`, `installMCP()`.

### Validation — Phase B
- `IntegrationHealthModel.checkAll()` populates all states.
- Calling `checkAll()` twice within 5 seconds skips the second check (logs a debug message).
- `checkAll(force: true)` always runs regardless of cache.
- Compatibility shims work for any callers still using old boolean properties.
- `swift test` passes.

---

## Phase C: Settings Window — 4 Tabs

**Goal**: New Settings window. Auto-sizing. Component versions visible. Four tabs.

### C.1: Create `Views/Settings/SettingsView.swift`

**Review fix**: Use SwiftUI `Settings {}` scene which auto-sizes per pane. No fixed `.frame()`. Set a floor of 580×500.

```swift
import SwiftUI
import ManifoldKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            AIAppsSettingsPane()
                .tabItem { Label("AI Apps", systemImage: "cpu") }
            MailSettingsPane()
                .tabItem { Label("Mail", systemImage: "envelope") }
            StorageSettingsPane()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        .frame(minWidth: 580, minHeight: 500)
    }
}
```

Register in `ManifoldApp.swift`:
```swift
Settings {
    SettingsView()
        .environment(store)
}
```

### C.2: Create `Views/Settings/GeneralSettingsPane.swift`

```swift
struct GeneralSettingsPane: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Toggle("Launch at Login", isOn: $store.launchAtLogin)
            }
            Section("Notifications") {
                Toggle("Agent session start and end", isOn: $store.notifyOnSessionEnd)
                Toggle("Access denied alerts", isOn: $store.notifyOnAccessDenied)
            }
        }
        .formStyle(.grouped)
    }
}
```

### C.3: Create `Views/Settings/AIAppsSettingsPane.swift`

Two agent cards with live health checks. Opens standalone connection sheets (not nested — these are top-level sheets from Settings, which is correct).

```swift
struct AIAppsSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        Form {
            Section {
                AgentSettingsCard(
                    agent: .cowork,
                    state: store.integrationHealth.claude,
                    onSetup: { showClaudeSheet = true }
                )
            }
            Section {
                AgentSettingsCard(
                    agent: .codex,
                    state: store.integrationHealth.codex,
                    onSetup: { showCodexSheet = true }
                )
            }
        }
        .formStyle(.grouped)
        .task { await store.integrationHealth.checkAll() }  // Rule 6: re-check on appear
        .sheet(isPresented: $showClaudeSheet) {
            ConnectClaudeSheet()
        }
        .sheet(isPresented: $showCodexSheet) {
            ConnectCodexSheet()
        }
    }
}
```

### C.4: `AgentSettingsCard` Component

```swift
struct AgentSettingsCard: View {
    let agent: TargetApp
    let state: AgentConnectionState
    let onSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(agent.color).frame(width: 8, height: 8)
                Text(agent.displayName).font(.headline)
                Spacer()
                OverallStatusBadge(status: state.overallStatus)
            }

            switch agent {
            case .cowork:
                CheckRow("App installed", status: state.appInstalled)
                CheckRow("MCP configured", status: state.mcpConfigured)
                CheckRow("Connection verified", status: state.connectionVerified)
            case .codex:
                CheckRow("CLI installed", status: state.cliInstalled)
                CheckRow("Manifold added", status: state.mcpAdded)
            }

            Button(actionLabel) { onSetup() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var actionLabel: String {
        switch state.overallStatus {
        case .connected: return "Reconnect"
        case .error: return "Repair Connection"
        default: return "Set Up \(agent.displayName)"
        }
    }
}
```

### C.5: `CheckRow` Component

```swift
struct CheckRow: View {
    let label: String
    let status: AgentConnectionStatus

    init(_ label: String, status: AgentConnectionStatus) {
        self.label = label
        self.status = status
    }

    var body: some View {
        HStack(spacing: 8) {
            statusIcon.frame(width: 16)
            Text(label).font(.callout)
            Spacer()
            Text(status.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .connected, .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown, .configured:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}

extension AgentConnectionStatus {
    var displayLabel: String {
        switch self {
        case .unknown: return ""
        case .checking: return "Checking…"
        case .notInstalled: return "Not found"
        case .installed: return "Installed"
        case .configured: return "Configured"
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}
```

### C.6: Create `Views/Settings/MailSettingsPane.swift`

Port accounts list from old email backup tab. "Add Account" opens `AddMailAccountSheet`.

### C.7: Create `Views/Settings/StorageSettingsPane.swift`

Port from old Storage tab. **Review fix**: Add version line in footer.

```swift
struct StorageSettingsPane: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Form {
            Section("Storage Location") { /* ... */ }
            Section("Maintenance") { /* ... */ }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Text("Manifold \(Bundle.main.shortVersionString) · MCP \(ManifoldKit.mcpVersion)")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }
}
```

### C.8: Delete old files + update references

- Delete `Views/SetupView.swift`
- Update all `SetupView()` references to `SettingsView()`

### Validation — Phase C
- Settings opens with ⌘, and shows 4 tabs.
- Window auto-sizes per pane, minimum 580×500.
- AI Apps tab shows live health checks that debounce correctly.
- Storage pane footer shows version line.
- No fixed 520×460 frame anywhere.

---

## Phase D: Setup Assistant — No Nested Sheets

**Goal**: 4-screen first-run assistant. The **biggest review fix**: Screen 2 shows connection checks **inline**, not as nested sheets. Screen 3 uses multi-select for initial folder setup.

### D.1: Create `Views/Setup/SetupAssistantView.swift`

```swift
struct SetupAssistantView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var screen: SetupScreen = .welcome

    enum SetupScreen: Int, CaseIterable {
        case welcome = 0, connectApps = 1, addData = 2, reviewFinish = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(SetupScreen.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= screen.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            .accessibilityLabel("Step \(screen.rawValue + 1) of \(SetupScreen.allCases.count)")

            Spacer()

            Group {
                switch screen {
                case .welcome: WelcomeScreen(advance: advance)
                case .connectApps: ConnectAppsInlineScreen(advance: advance, skip: advance)
                case .addData: AddDataScreen(advance: advance, skip: advance)
                case .reviewFinish: ReviewFinishScreen(finish: finish)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            if screen.rawValue > 0 && screen != .reviewFinish {
                HStack {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            screen = SetupScreen(rawValue: screen.rawValue - 1) ?? .welcome
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 580, height: 500)
        .interactiveDismissDisabled(screen != .reviewFinish)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if let next = SetupScreen(rawValue: screen.rawValue + 1) { screen = next }
        }
    }

    private func finish() {
        store.hasCompletedOnboarding = true
        dismiss()
    }
}
```

### D.2: Screen 1 — Welcome

**Review fixes**: "Get Started" → "Continue".

```swift
private struct WelcomeScreen: View {
    let advance: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Manifold controls what AI agents see on your Mac.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Nothing is shared until you decide. Every change is versioned automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Continue") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 48)
    }
}
```

### D.3: Screen 2 — Connect AI Apps (INLINE — No Nested Sheets)

**This is the critical review fix.** The old plan opened `ConnectClaudeSheet` and `ConnectCodexSheet` as `.sheet()` modals from this screen — creating a jarring sheet-within-sheet experience. The fix: render the same `LiveCheckRow` content directly on this screen. Each agent gets a card with inline checks and an inline action button. No sub-sheets.

```swift
private struct ConnectAppsInlineScreen: View {
    let advance: () -> Void
    let skip: () -> Void
    @Environment(ManifoldStore.self) var store
    @State private var claudeInstalling = false
    @State private var codexAdding = false
    @State private var codexError: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect Claude or Codex.")
                .font(.title2.weight(.semibold))

            Text("Manifold works with either or both. You can add more later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                // CLAUDE — inline checks
                InlineAgentSetup(
                    agentName: "Claude",
                    agentColor: .blue,
                    checks: [
                        InlineCheck(
                            label: "App installed",
                            status: store.integrationHealth.claude.appInstalled,
                            actionLabel: "Download",
                            action: { NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!) }
                        ),
                        InlineCheck(
                            label: "MCP configured",
                            status: store.integrationHealth.claude.mcpConfigured,
                            actionLabel: claudeInstalling ? "Installing…" : "Install",
                            action: {
                                claudeInstalling = true
                                store.installManifoldForClaude()
                                Task {
                                    await store.integrationHealth.checkClaude()
                                    claudeInstalling = false
                                }
                            }
                        ),
                        InlineCheck(
                            label: "Connection verified",
                            status: store.integrationHealth.claude.connectionVerified,
                            actionLabel: nil,
                            action: nil  // No user action — this resolves when Claude connects
                        )
                    ]
                )

                // CODEX — inline checks (2 only)
                InlineAgentSetup(
                    agentName: "Codex",
                    agentColor: .purple,
                    checks: [
                        InlineCheck(
                            label: "CLI installed",
                            status: store.integrationHealth.codex.cliInstalled,
                            actionLabel: "Install",
                            action: { NSWorkspace.shared.open(URL(string: "https://openai.com/index/introducing-codex/")!) }
                        ),
                        InlineCheck(
                            label: "Manifold added",
                            status: store.integrationHealth.codex.mcpAdded,
                            actionLabel: codexAdding ? "Adding…" : "Add to Codex",
                            action: {
                                codexAdding = true
                                codexError = nil
                                store.addManifoldToCodex { error in
                                    codexAdding = false
                                    codexError = error
                                }
                            }
                        )
                    ],
                    errorMessage: codexError
                )
            }
            .frame(maxWidth: 440)

            // Continue when at least one agent has some configuration
            if store.integrationHealth.claude.overallStatus != .notInstalled
                || store.integrationHealth.codex.overallStatus != .notInstalled {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Skip, I'll do this later") { skip() }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .task { await store.integrationHealth.checkAll(force: true) }
    }
}
```

**`InlineAgentSetup`** — Compact card with agent header + check rows rendered directly:

```swift
struct InlineAgentSetup: View {
    let agentName: String
    let agentColor: Color
    let checks: [InlineCheck]
    var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(agentColor).frame(width: 8, height: 8)
                Text(agentName).font(.callout.weight(.medium))
            }

            ForEach(checks) { check in
                LiveCheckRow(
                    label: check.label,
                    status: check.status,
                    action: check.action,
                    actionLabel: check.actionLabel
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 36)
            }
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

struct InlineCheck: Identifiable {
    let id = UUID()
    let label: String
    let status: AgentConnectionStatus
    let actionLabel: String?
    let action: (() -> Void)?
}
```

**Why this is better**: The user sees the checks progress in real-time on the same screen they're already looking at. No modal slides up, no context switch, no "where did the setup assistant go?" moment. The standalone `ConnectClaudeSheet` and `ConnectCodexSheet` still exist for the Settings context (Phase E), where a modal is the correct pattern because the user is already in a stable, non-linear environment.

### D.4: Screen 3 — Add Your Data (Multi-Select, No Per-Item Review Sheet)

**Review fix**: Initial setup should use a multi-select folder picker, not trigger the Review sheet per folder.

```swift
private struct AddDataScreen: View {
    let advance: () -> Void
    let skip: () -> Void
    @Environment(ManifoldStore.self) var store
    @State private var showMailSetup = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose what to share.")
                .font(.title2.weight(.semibold))

            Text("Add folders or email accounts. Agents can only see what you allow.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                // Folders section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Folders", systemImage: "folder")
                        .font(.callout.weight(.medium))

                    ForEach(store.approvedSources, id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(path.shortenedPath)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                        }
                    }

                    // Multi-select folder picker — adds everything at once.
                    // NO per-item Review sheet. This entire screen IS the review context.
                    Button("Add Folders…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = true
                        panel.message = "Select folders to share with AI agents"
                        panel.prompt = "Add"
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                store.addSourceDirect(url)  // Bypasses Review sheet
                            }
                        }
                    }
                    .controlSize(.small)
                }

                Divider()

                // Email section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Email", systemImage: "envelope")
                        .font(.callout.weight(.medium))

                    ForEach(store.emailAccounts.accounts) { account in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(account.displayName).font(.caption)
                        }
                    }

                    Button("Add Email Account…") { showMailSetup = true }
                        .controlSize(.small)
                }
            }
            .padding(20)
            .frame(maxWidth: 400)
            .background(.background, in: .rect(cornerRadius: 10))

            if !store.approvedSources.isEmpty || !store.emailAccounts.accounts.isEmpty {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Skip for now") { skip() }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 48)
        .sheet(isPresented: $showMailSetup) {
            AddMailAccountSheet()
        }
    }
}
```

**Key decision**: `store.addSourceDirect(url)` is a new method that adds a source without triggering the Review sheet. This is correct because during onboarding, the user is explicitly choosing what to share — the entire screen IS the commitment surface. The per-checkbox Review sheet pattern is for post-setup use in the Files tab, where broadening should feel deliberate.

### D.5: Screen 4 — Review & Finish

**Review fixes**: "Open Manifold" → "Done". The user is already in Manifold.

```swift
private struct ReviewFinishScreen: View {
    let finish: () -> Void
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("You're ready.")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                SummaryRow("AI Apps", status: agentSummary,
                    done: store.integrationHealth.claude.overallStatus == .connected
                        || store.integrationHealth.codex.overallStatus == .connected)
                SummaryRow("Folders", status: folderSummary,
                    done: !store.approvedSources.isEmpty)
                SummaryRow("Email", status: emailSummary,
                    done: !store.emailAccounts.accounts.isEmpty)
            }
            .frame(maxWidth: 360)

            Text("You can change all of this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 48)
    }
}
```

### D.6: Wire into app launch

```swift
// ManifoldApp.swift — replace existing onboarding:
.sheet(isPresented: Binding(
    get: { !store.hasCompletedOnboarding },
    set: { if !$0 { store.hasCompletedOnboarding = true } }
)) {
    SetupAssistantView()
}
```

### D.7: Delete `Views/OnboardingView.swift`

### Validation — Phase D
- First launch shows 4-screen Setup Assistant.
- Screen 2 shows inline checks — NO sheet opens within the assistant.
- Screen 3 uses multi-select folder picker (NSOpenPanel with `allowsMultipleSelection`).
- Screen 3 does NOT trigger the Review sheet per folder.
- "Continue" on Welcome (not "Get Started").
- "Done" on final screen (not "Open Manifold").
- Back button works on screens 1–2.
- Subsequent launches skip the assistant.

---

## Phase E: Connection Sheets — For Settings Only

**Goal**: Three standalone sheets used from Settings > AI Apps. These are NOT used in the Setup Assistant (that's Phase D's inline approach). These sheets have been polished per the review: 2 footer buttons, consistent sizing, inline refresh.

### E.1: `LiveCheckRow` — With Inline Refresh

**Review fix**: Remove "Check Again" from sheet footer. Add a ↻ refresh button per failed check row.

```swift
struct LiveCheckRow: View {
    let label: String
    let status: AgentConnectionStatus
    let action: (() -> Void)?
    let actionLabel: String?
    var onRefresh: (() async -> Void)? = nil  // NEW: inline refresh

    var body: some View {
        HStack(spacing: 12) {
            statusIcon.frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body)
                Text(status.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action button when check fails
            if status == .notInstalled || status == .error {
                if let actionLabel, let action {
                    Button(actionLabel, action: action)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }

                // Inline refresh (review fix: replaces footer "Check Again")
                if let onRefresh {
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Check again")
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .connected, .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Image(systemName: "circle")
                .font(.title2).foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(.orange)
        case .unknown, .configured:
            Image(systemName: "circle.dashed")
                .font(.title2).foregroundStyle(.secondary)
        }
    }
}
```

### E.2: Create `Views/Setup/ConnectClaudeSheet.swift`

**Review fixes**:
- Size: 460×420
- Footer: 2 buttons only (Cancel + Done). No "Check Again."
- Primary install action: ConfigWriter (silent). `.mcpb` in disclosure group only.
- Each failed row has inline ↻ refresh.

```swift
struct ConnectClaudeSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Circle().fill(Color.blue).frame(width: 12, height: 12)
                Text("Connect Claude").font(.title3.weight(.semibold))
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                LiveCheckRow(
                    label: "Claude Desktop installed",
                    status: store.integrationHealth.claude.appInstalled,
                    action: { NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!) },
                    actionLabel: "Download",
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                LiveCheckRow(
                    label: "MCP configured",
                    status: store.integrationHealth.claude.mcpConfigured,
                    action: {
                        // PRIMARY: ConfigWriter (silent, one-click)
                        installing = true
                        store.installManifoldForClaudeViaConfigWriter()
                        Task {
                            await store.integrationHealth.checkClaude()
                            installing = false
                        }
                    },
                    actionLabel: installing ? "Installing…" : "Install",
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                LiveCheckRow(
                    label: "Connection verified",
                    status: store.integrationHealth.claude.connectionVerified,
                    action: nil,
                    actionLabel: nil,
                    onRefresh: { await store.integrationHealth.checkClaude() }
                )

                // Technical detail — includes .mcpb manual alternative
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                        DetailLine("Config", value: "~/Library/Application Support/Claude/claude_desktop_config.json")

                        if let mcpbURL = Bundle.main.url(forResource: "manifold", withExtension: "mcpb") {
                            Divider().padding(.vertical, 4)
                            Text("Prefer the official extension?")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Button("Reveal .mcpb in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([mcpbURL])
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            Spacer()

            // Footer — TWO buttons only (review fix)
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                if store.integrationHealth.claude.mcpConfigured == .installed {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .task { await store.integrationHealth.checkAll(force: true) }
    }
}
```

**Install method — ConfigWriter as primary**:

```swift
// ManifoldStore extension:
func installManifoldForClaudeViaConfigWriter() {
    // ConfigWriter writes claude_desktop_config.json directly.
    // This is the primary path — silent, one-click, battle-tested.
    do {
        let destPath = Self.mcpBinaryPath
        let destURL = URL(fileURLWithPath: destPath)
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ConfigWriter(binaryPath: destPath).installAll()
    } catch {
        integrationHealth.claude.errorDetail = error.localizedDescription
        integrationHealth.claude.mcpConfigured = .error
    }
}
```

### E.3: Create `Views/Setup/ConnectCodexSheet.swift`

**Review fixes**:
- Size: 460×420 (same as Claude — review called out the 40px difference)
- Footer: 2 buttons only
- Inline ↻ refresh per row

```swift
struct ConnectCodexSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Circle().fill(Color.purple).frame(width: 12, height: 12)
                Text("Connect Codex").font(.title3.weight(.semibold))
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                LiveCheckRow(
                    label: "Codex installed",
                    status: store.integrationHealth.codex.cliInstalled,
                    action: { NSWorkspace.shared.open(URL(string: "https://openai.com/index/introducing-codex/")!) },
                    actionLabel: "Install",
                    onRefresh: { await store.integrationHealth.checkCodex() }
                )

                LiveCheckRow(
                    label: "Manifold added",
                    status: store.integrationHealth.codex.mcpAdded,
                    action: {
                        adding = true
                        addError = nil
                        store.addManifoldToCodex { error in
                            adding = false
                            addError = error
                        }
                    },
                    actionLabel: adding ? "Adding…" : "Add to Codex",
                    onRefresh: { await store.integrationHealth.checkCodex() }
                )

                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 36)
                }

                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                        DetailLine("Config", value: "~/.codex/config.toml")
                        DetailLine("Command", value: "codex mcp add manifold -- \(ManifoldStore.mcpBinaryPath) --agent codex")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            Spacer()

            // Footer — TWO buttons only
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                if store.integrationHealth.codex.mcpAdded == .installed {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)  // Same size as Claude (review fix)
        .task { await store.integrationHealth.checkCodex() }
    }
}
```

### E.4: Create `Views/Setup/AddMailAccountSheet.swift`

Provider-first flow wrapping existing `OAuthManager`. Same as prior plan — this wasn't critiqued in the review.

### Validation — Phase E
- Connection sheets have exactly 2 footer buttons (Cancel + Done).
- No "Check Again" footer button anywhere.
- Each failed check row has a ↻ refresh icon.
- Both sheets are 460×420.
- Claude "Install" button runs ConfigWriter silently (no Finder reveal).
- `.mcpb` is mentioned only in the disclosure group.
- Codex stderr is surfaced inline.

---

## Phase F: Final Audit

### F.1: Copy Audit — Every User-Facing String

Walk the entire UI and verify:

| Old | New | Where |
|-----|-----|-------|
| "Start Tracked Work Block" | "Track Changes" | Overview, Review sheet, keyboard shortcut |
| "Work Block" | "Tracking Changes" | Banner / toolbar indicator |
| "Finish & Review" | "Review Changes" | Banner / toolbar |
| "Review & Update Access" (button) | "Update Access…" | Agent cards |
| "Review & Update Access" (menu) | "Review Access…" | Menu bar, ⌘⇧R |
| "Get Started" | "Continue" | Setup Assistant Screen 1 |
| "Open Manifold" | "Done" | Setup Assistant Screen 4 |
| "Check Again" | (removed) | Connection sheets |

### F.2: Accessibility Audit

- [ ] AgentFocusControl has `.accessibilityHint()`
- [ ] Undo toast persists when VoiceOver is running
- [ ] ⌘Z undoes last narrowing action
- [ ] All `LiveCheckRow` status icons have accessibility labels
- [ ] Progress dots in Setup Assistant have accessibility label
- [ ] 44pt minimum touch targets on all checkboxes

### F.3: Performance Audit

- [ ] `IntegrationHealthModel.checkAll()` debounces correctly (5-sec cache)
- [ ] `checkAll(force: true)` bypasses cache
- [ ] `DomainModel.computeDomains()` runs off main actor
- [ ] Domains table uses `List` (virtualized) not `ScrollView + ForEach`

### F.4: Material Audit

- [ ] Top bar tabs in `.toolbar {}` with `.principal` placement → automatic glass ✅
- [ ] Work block indicator in toolbar (not a VStack banner)
- [ ] Agent cards use shadow + stroke border (not colored left border) ✅
- [ ] Data rows are stable opaque, not glassed
- [ ] Inspector and Activity drawer frames get glass on border, not on content

### F.5: Build & Test

```bash
swift build  # Zero warnings
swift test   # All pass
```

---

## File Summary

### New Files (14)

| File | Phase |
|------|-------|
| `Components/TrackChangesToolbarContent.swift` | A |
| `Models/AgentConnectionState.swift` | B |
| `Models/IntegrationHealthModel.swift` | B |
| `Views/Settings/SettingsView.swift` | C |
| `Views/Settings/GeneralSettingsPane.swift` | C |
| `Views/Settings/AIAppsSettingsPane.swift` | C |
| `Views/Settings/MailSettingsPane.swift` | C |
| `Views/Settings/StorageSettingsPane.swift` | C |
| `Components/AgentSettingsCard.swift` | C |
| `Components/CheckRow.swift` | C |
| `Views/Setup/SetupAssistantView.swift` | D |
| `Views/Setup/ConnectClaudeSheet.swift` | E |
| `Views/Setup/ConnectCodexSheet.swift` | E |
| `Views/Setup/AddMailAccountSheet.swift` | E |

### Modified Files (8)

| File | Phase | Change |
|------|-------|--------|
| `Views/AgentPolicyCard.swift` | A | Button label, remove hover-to-red |
| `Views/OverviewView.swift` | A | "Track Changes" label |
| `Views/WorkBlockBannerView.swift` | A | Rename labels (kept as fallback) |
| `Views/MainView.swift` | A | Banner → toolbar, activity independence |
| `Views/ReviewAccessSheet.swift` | A | Button label update |
| `ManifoldApp.swift` | A, C, D | Menu labels, Settings scene, onboarding wire |
| `Models/SetupModel.swift` | B | Slim to preferences only |
| `ManifoldStore.swift` | B | Wire IntegrationHealthModel, add addSourceDirect() |

### Deleted Files (2)

| File | Phase |
|------|-------|
| `Views/SetupView.swift` | C |
| `Views/OnboardingView.swift` | D |

---

## Review Critique Coverage — Proof of Completeness

Every single critique from `DESIGN-REVIEW-APPLE-QUALITY.md` is accounted for:

| Review Section | Score Before | Addressed In | Expected Score After |
|---------------|-------------|-------------|---------------------|
| 1. Information Architecture (4.5) | Button label too long | A.2 | 5.0 |
| 2. Navigation (4.0) | Banner placement, drawer/inspector | A.4, A.5 | 4.5 |
| 3. Visual Design (4.0) | Left border, glass on top bar | Already correct in code | 4.5 |
| 4. Interaction (4.5) | Per-checkbox fatigue, hover-to-red | D.4, A.3 | 5.0 |
| 5. Settings (4.0) | Window size, version info | C.1, C.7 | 4.5 |
| 6. Onboarding (3.5) | Nested sheets, CTA labels | D.3, D.2, D.5 | 4.5 |
| 7. Connection Sheets (3.5) | 3 buttons, size, install path | E.1, E.2, E.3 | 4.5 |
| 8. Copy (4.0) | "Work Block" jargon, label length | A.1, A.2 | 4.5 |
| 9. Accessibility (4.0) | Focus hint, undo toast | A.6, A.7 | 4.5 |
| 10. Performance (3.5) | Debounce, domain pagination | B.2, A.8 | 4.5 |
| **Weighted Average** | **3.8** | | **4.6** |
