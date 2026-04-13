# Manifold v4.1 — Claude Code Implementation Plan

> **What this document is**: Step-by-step instructions for Claude Code to build the v4.1 UI in native SwiftUI, targeting macOS 26 Liquid Glass. Every phase tells you what to build, which files to touch, and what to validate before moving on.
>
> **What this document is NOT**: An HTML wireframe recreation guide. The wireframe (`design/manifold-wireframe-v4.html`) is a visual reference only. Build native SwiftUI — use `NavigationSplitView`, `Table`, `.inspector()`, `.sheet()`, `@Observable`, Liquid Glass materials. If the wireframe shows a CSS pattern, translate it to the SwiftUI equivalent. The spec (`design/LAYOUT-SPEC-v4.md`) is the authoritative source of truth for what to build.
>
> **Required skill**: Before writing ANY SwiftUI code, invoke the `swiftui-pro` skill. It contains macOS 26 patterns, Liquid Glass API usage, and Apple HIG conventions that this plan depends on.

---

## Prerequisites

### Read these files first (in order)
1. `design/LAYOUT-SPEC-v4.md` — The authoritative UI spec. This defines WHAT to build.
2. This file — Defines HOW to build it.
3. `design/manifold-wireframe-v4.html` — Open in a browser for visual reference only. Do not port HTML.
4. `design/navigation-flows-v4.mermaid` — Navigation graph for reference.

### Invoke the `swiftui-pro` skill
Before writing any view code, invoke the `swiftui-pro` skill in Claude Code. It has macOS 26 Liquid Glass patterns, proper `NavigationSplitView` usage, `@Observable` patterns, and `.inspector()` / `.sheet()` best practices. Follow its guidance over any generic SwiftUI patterns.

### Understand the existing codebase structure
```
ManifoldApp/ManifoldApp/
├── Views/
│   ├── MainView.swift              ← 3-col NavigationSplitView (rewrite)
│   ├── SidebarView.swift           ← 5-item global sidebar (DELETE)
│   ├── HomeView.swift              ← Session dashboard (rewrite → OverviewView)
│   ├── SessionView.swift           ← Session file browser (DELETE)
│   ├── PresetPickerView.swift      ← Session presets (DELETE)
│   ├── FilesView.swift             ← File explorer (MODIFY)
│   ├── SourcesView.swift           ← Source management (refactor → SourcesTableView)
│   ├── HistoryView.swift           ← 3-mode history (demote to drawer)
│   ├── ActivityView.swift          ← Filters, search, events (KEEP, wrap in drawer)
│   ├── ActivityRow.swift           ← Event row (KEEP)
│   ├── CommandPaletteView.swift    ← ⌘K palette (KEEP)
│   ├── OnboardingView.swift        ← First-run (KEEP)
│   ├── SetupView.swift             ← Setup flow (KEEP)
│   ├── Dashboard/                  ← Dashboard sub-views (DELETE after extracting reusable parts)
│   ├── Email/                      ← Full email sub-tree (MODIFY, add Domains mode)
│   │   ├── EmailView.swift
│   │   ├── Sidebar/EmailSidebar.swift
│   │   ├── MessageList/
│   │   ├── ReadingPane/
│   │   ├── Search/
│   │   ├── ShareWithCowork/
│   │   └── SmartMailbox/
│   ├── Versions/                   ← Version views (KEEP, move to Inspector)
│   └── Library/
├── Models/
│   ├── ManifoldStore.swift         ← @Observable root store (MODIFY heavily)
│   ├── SessionModel.swift          ← Session lifecycle (DELETE)
│   ├── ManifoldTypes.swift         ← Type definitions (KEEP)
│   ├── HistoryModel.swift          ← History data (MODIFY for activity)
│   ├── EmailAccountModel.swift     ← Email accounts (KEEP)
│   └── ...
├── Components/
│   ├── AgentBadge.swift            ← Reuse
│   ├── StatusBadge.swift           ← Reuse
│   ├── DiffView.swift              ← Reuse
│   ├── TimeLabel.swift             ← Reuse
│   └── Spacing.swift               ← Reuse

Sources/ManifoldKit/                ← Backend stores (mostly unchanged)
├── GrantStore.swift                ← Add standing grant support
├── GrantTypes.swift                ← TargetApp enum lives here
├── DatabaseMigrator.swift          ← Add new tables
├── MaterializationEngine.swift     ← Work blocks only (unchanged)
├── PromoteEngine.swift             ← Work blocks only (unchanged)
├── ManifoldBridge.swift (in MCP)   ← Replace requireGrant() with resolvePolicy()
└── ... (ContentStore, SnapshotStore, AuditStore, EmailStore, etc. — unchanged)
```

### Key architecture facts
- **`TargetApp.cowork`** = "Claude" in the UI. `TargetApp.codex` = "Codex". The enum is in `GrantTypes.swift`. Add a `displayName` computed property if one doesn't already exist.
- **Swift 6** strict concurrency. All stores are `actor` or `@MainActor`.
- **ManifoldKit** is a separate SPM target. The app imports it. New data types go here.
- **ManifoldMCP** is a separate executable. `ManifoldBridge` is an `actor`.
- **`@Observable`** macro for all view models. NOT `ObservableObject`/`@Published`.
- **`@Environment`** for dependency injection. `ManifoldStore` is injected via `.environment()`.
- **macOS 26 / Liquid Glass**: Use `.glassEffect()`, `.containerBackground()`, semantic materials. The `swiftui-pro` skill has the specific API patterns.
- **`NavigationSplitView`** is the established pattern. Files and Emails tabs each get their own.
- **`.inspector()`** for the right panel. Already wired in `MainView.swift`.
- **`.sheet()`** for the Review & Update Access surface. Use `.presentationDetents` for full-height.

---

## Phase 0: Data Layer — New Types + Stores (no UI changes)

**Goal**: Add `AgentAccessPolicy`, `TemporaryReveal`, `WorkBlockRecord` to ManifoldKit. All existing tests must still pass. Zero UI changes.

### Step 0.1: Create `Sources/ManifoldKit/AgentAccessPolicy.swift`

Define these types (from LAYOUT-SPEC-v4.md §Backend):

```swift
import Foundation

/// Persistent standing access policy per agent.
public struct AgentAccessPolicy: Codable, Sendable {
    public let agent: TargetApp
    public var allowedSourceIDs: Set<String>
    public var allowedEmailDomains: Set<String>
    public var emailSensitivity: EmailSensitivity
    public var isPaused: Bool
    public var hasCompletedFirstGrant: Bool
    public var updatedAt: Date
}

/// Single-email temporary visibility override.
public struct TemporaryReveal: Codable, Sendable, Identifiable {
    public let id: String
    public let agent: TargetApp
    public let messageID: String
    public let expiresAtRunID: String?
    public let createdAt: Date
}

/// Optional tracked work block with snapshot/promote lifecycle.
public struct WorkBlockRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let agent: TargetApp
    public let baselineSnapshotIDs: [String]
    public let policyAtStart: AgentAccessPolicy
    public let startedAt: Date
    public var endedAt: Date?
    public var status: WorkBlockStatus
}

public enum WorkBlockStatus: String, Codable, Sendable {
    case active, paused, reviewing, promoted, discarded
}

/// Email sensitivity levels (may already exist — check EmailSensitivityFilter).
public enum EmailSensitivity: String, Codable, Sendable {
    case strict, moderate, open
}
```

> **Note**: Check if `EmailSensitivity` already exists in `EmailSensitivityFilter.swift`. If it does, reuse it. If it's called something different, alias or rename.

### Step 0.2: Create `Sources/ManifoldKit/PolicyStore.swift`

```swift
/// Actor for CRUD on AgentAccessPolicy. SQLite-backed.
public actor PolicyStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) { self.db = db }

    public func policy(for agent: TargetApp) throws -> AgentAccessPolicy? { ... }
    public func allPolicies() throws -> [AgentAccessPolicy] { ... }
    public func updatePolicy(_ policy: AgentAccessPolicy) throws { ... }
    public func createDefaultPolicy(for agent: TargetApp) throws -> AgentAccessPolicy { ... }
}
```

### Step 0.3: Create `Sources/ManifoldKit/WorkBlockStore.swift`

```swift
/// Actor for CRUD on WorkBlockRecord. SQLite-backed.
public actor WorkBlockStore {
    private let db: DatabaseConnection

    public init(db: DatabaseConnection) { self.db = db }

    public func activeBlock(for agent: TargetApp) throws -> WorkBlockRecord? { ... }
    public func startBlock(agent: TargetApp, sourceIDs: [String], policy: AgentAccessPolicy) throws -> WorkBlockRecord { ... }
    public func endBlock(id: String, status: WorkBlockStatus) throws { ... }
    public func allBlocks(for agent: TargetApp) throws -> [WorkBlockRecord] { ... }
}
```

### Step 0.4: Add database migration in `DatabaseMigrator.swift`

Add a new migration (next version number) that creates tables:
- `agent_access_policies` — columns matching `AgentAccessPolicy` fields, primary key on `agent`
- `temporary_reveals` — columns matching `TemporaryReveal` fields
- `work_block_records` — columns matching `WorkBlockRecord` fields

### Step 0.5: Update `GrantStore.swift`

Add support for standing grants:
- `createStandingGrant(for agent: TargetApp, sourceIDs: [String])` — creates a grant with no timeout
- `standingGrant(for agent: TargetApp)` — fetches the standing grant

Standing grants coexist with work block grants. They have different lifecycles.

### Step 0.6: Write tests

In `Tests/ManifoldKitTests/`:
- `PolicyStoreTests.swift` — CRUD, default policy creation, update
- `WorkBlockStoreTests.swift` — start, end, active block query
- Verify existing tests still pass: `swift test`

### Validation
```bash
swift test  # All pass, zero failures
```

---

## Phase 1: MCP Bridge Adaptation

**Goal**: `ManifoldBridge` resolves access via `PolicyStore` instead of requiring an active grant. Standing access works without session start.

### Step 1.1: Add `PolicyStore` to `ManifoldBridge`

In `Sources/ManifoldMCP/ManifoldBridge.swift`:
- Add `private let policyStore: PolicyStore` property
- Update `init()` to accept `PolicyStore`
- Add `private func resolvePolicy() async throws -> AgentAccessPolicy`

### Step 1.2: Replace `requireGrant()` call sites

Create a dual-path resolution:
```swift
private func resolveAccess() async throws -> AccessResolution {
    // 1. Check for active work block → use materialized workspace
    if let block = try await workBlockStore.activeBlock(for: targetApp),
       block.status == .active {
        return .workBlock(block)
    }
    // 2. Fall back to standing access policy
    guard let policy = try await policyStore.policy(for: targetApp) else {
        throw ManifoldError.noAccessConfigured
    }
    guard !policy.isPaused else {
        throw ManifoldError.accessPaused
    }
    return .standingAccess(policy)
}
```

### Step 1.3: Update tool handlers

In `Sources/ManifoldMCP/ToolHandlers.swift`, update `listFiles`, `readFile`, `writeFile`, `searchFiles` to use the new resolution path. Standing access = direct file reads. Work block = materialized workspace.

### Step 1.4: Update `getStatus()` tool

Return policy state instead of grant state. Include: allowed sources, email domains, sensitivity, pause state, active work block info.

### Validation
- Write integration tests: standing access allows reads, paused denies all, work block routes writes
- `swift test`

---

## Phase 2: Navigation Restructure

**Goal**: Replace the 5-item global sidebar with a 3-tab top bar. Overview is full-width. Files and Emails each get their own sidebar.

> **IMPORTANT**: Invoke the `swiftui-pro` skill before starting this phase. You need macOS 26 Liquid Glass patterns for the top bar.

### Step 2.1: Define new navigation enum

In `ManifoldStore.swift`, replace `SidebarItem`:
```swift
enum AppTab: String, Hashable, CaseIterable {
    case overview
    case files
    case emails
}
```

Replace `selectedSidebarItem` with `selectedTab: AppTab = .overview`.

### Step 2.2: Rewrite `MainView.swift`

The new structure:

```swift
struct MainView: View {
    @Environment(ManifoldStore.self) var store
    @State private var showReviewSheet = false

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            // Top bar with segmented control
            TopBarView(selectedTab: $store.selectedTab)

            // Work Block Banner (global, when active)
            if store.workBlock.hasActiveBlock {
                WorkBlockBannerView()
            }

            // Tab content
            switch store.selectedTab {
            case .overview:
                OverviewView()          // Full-width, no NavigationSplitView
            case .files:
                FilesTabView()          // Has its own NavigationSplitView
            case .emails:
                EmailsTabView()         // Has its own NavigationSplitView
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            ReviewAccessSheet()
                .presentationDetents([.large])  // Full-height
        }
        .overlay { /* Command palette overlay — keep existing */ }
        .onKeyPress(/* keyboard shortcuts — see §Keyboard Shortcuts below */)
    }
}
```

**Key decisions**:
- **No outer `NavigationSplitView`**. Each tab manages its own layout internally.
- **`TopBarView` uses Liquid Glass material** (`.glassEffect()` from swiftui-pro skill).
- **Work Block Banner sits between top bar and tab content** — visible on all tabs.
- **The `.sheet()` for Review & Update Access is owned by MainView** so it's accessible from any tab.

### Step 2.3: Create `Views/TopBarView.swift`

```swift
struct TopBarView: View {
    @Binding var selectedTab: AppTab
    @Environment(ManifoldStore.self) var store

    var body: some View {
        HStack {
            // Left: App icon + name
            Label("Manifold", image: "AppIcon")

            Spacer()

            // Center: Segmented control
            Picker("Tab", selection: $selectedTab) {
                Text("Overview").tag(AppTab.overview)
                Text("Files").tag(AppTab.files)
                Text("Emails").tag(AppTab.emails)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            // Right: Search + agent indicators
            // ⌘K search button
            // Agent connection dots
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .glassEffect()  // Liquid Glass — check swiftui-pro skill for exact API
    }
}
```

### Step 2.4: Delete `SidebarView.swift`

It's fully replaced by per-tab sidebars. Remove all references.

### Step 2.5: Update keyboard shortcuts

In `ManifoldApp.swift` (the `@main` App struct), replace session shortcuts:
- Remove: ⌘⇧S (start session), ⌘⇧E (end session)
- Add: ⌘1/2/3 (tab switching), ⌘⇧R (Review & Update Access), ⌘⇧W (Work Block toggle), ⌘⇧P (Pause/Resume), ⌘⇧A (Activity drawer), ⌘I (Inspector)

### Validation
- App launches with 3 tabs
- Overview is full-width (no sidebar column)
- Files and Emails show placeholder content with their own sidebars
- Keyboard shortcuts work
- Liquid Glass renders on top bar

---

## Phase 3: View Models — PolicyModel, WorkBlockModel, DomainModel

**Goal**: Observable view models that bridge ManifoldKit stores to SwiftUI views.

### Step 3.1: Create `Models/PolicyModel.swift`

```swift
@Observable
@MainActor
class PolicyModel {
    var claudePolicy: AgentAccessPolicy?
    var codexPolicy: AgentAccessPolicy?

    private let policyStore: PolicyStore

    func loadPolicies() async { ... }
    func updateFileAccess(agent: TargetApp, sourceID: String, included: Bool) async { ... }
    func updateEmailAccess(agent: TargetApp, domain: String, included: Bool) async { ... }
    func updateSensitivity(agent: TargetApp, level: EmailSensitivity) async { ... }
    func pauseAgent(_ agent: TargetApp) async { ... }
    func resumeAgent(_ agent: TargetApp) async { ... }

    func policy(for agent: TargetApp) -> AgentAccessPolicy? {
        switch agent {
        case .cowork: return claudePolicy   // .cowork = Claude/Cowork in the UI
        case .codex: return codexPolicy
        }
    }
}
```

### Step 3.2: Create `Models/WorkBlockModel.swift`

```swift
@Observable
@MainActor
class WorkBlockModel {
    var activeBlocks: [TargetApp: WorkBlockRecord] = [:]
    var hasActiveBlock: Bool { !activeBlocks.isEmpty }

    func startBlock(agent: TargetApp) async { ... }
    func finishBlock(agent: TargetApp) async -> PromoteResult { ... }
    func pauseBlock(agent: TargetApp) async { ... }
    func stopBlock(agent: TargetApp) async { ... }  // destructive
}
```

### Step 3.3: Create `Models/DomainModel.swift`

```swift
@Observable
@MainActor
class DomainModel {
    var domains: [DomainAggregate] = []

    struct DomainAggregate: Identifiable {
        var id: String { domain }
        let domain: String
        let category: DomainCategory  // work, automated, personal
        let emailCount: Int
        let isHiddenBySensitivity: Bool
        let hiddenReason: String?     // "banking", "health", "2FA"
    }

    func computeDomains(from emailStore: EmailStore) async { ... }
}
```

### Step 3.4: Wire into `ManifoldStore`

Replace `let session: SessionModel` with:
```swift
let policy: PolicyModel
let workBlock: WorkBlockModel
let domainModel: DomainModel
```

Remove `SessionModel` references. Keep `history`, `storage`, `setup`, `emailAccounts`.

### Validation
- `ManifoldStore` initializes without crash
- `PolicyModel` loads policies from database
- No SessionModel references remain in compilation

---

## Phase 4: Agent Focus Control + Work Block Banner

**Goal**: Reusable components used across multiple tabs.

### Step 4.1: Create `Components/AgentFocusControl.swift`

```swift
enum AgentFocusMode: String, CaseIterable {
    case claude, codex, compare
}

struct AgentFocusControl: View {
    @Binding var mode: AgentFocusMode

    var body: some View {
        Picker("Agent", selection: $mode) {
            Text("Claude").tag(AgentFocusMode.claude)
            Text("Codex").tag(AgentFocusMode.codex)
            Text("Compare").tag(AgentFocusMode.compare)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}
```

### Step 4.2: Create `Views/WorkBlockBannerView.swift`

```swift
struct WorkBlockBannerView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        // Horizontal bar: agent dot, "Work Block — Claude · 1h 28m · 12 modified",
        // [Finish & Review] [Pause Access] [Stop Now ✕]
        HStack { ... }
        .frame(height: 44)
        .background(.bar)  // Or appropriate Liquid Glass treatment
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

Use the animation from LAYOUT-SPEC: `spring(response: 0.4, dampingFraction: 0.85)` for appear.

"Stop Now" must show a confirmation alert:
```swift
.confirmationDialog("Stop this work block?", isPresented: $showStopConfirm) {
    Button("Discard Changes", role: .destructive) { ... }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("All changes since baseline will be discarded. This cannot be undone.")
}
```

### Validation
- `AgentFocusControl` renders and toggles between 3 states
- `WorkBlockBannerView` appears/disappears with animation
- "Stop Now" shows confirmation before acting

---

## Phase 5: Overview Tab

**Goal**: Full-width overview with simplified agent cards. No sidebar.

### Step 5.1: Create `Views/OverviewView.swift`

```swift
struct OverviewView: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AgentPolicyCard(agent: .cowork)
                AgentPolicyCard(agent: .codex)

                Button("Start Tracked Work Block") {
                    store.requestReviewSheet(reason: .startWorkBlock)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 720)
            .padding(24)
        }
        .frame(maxWidth: .infinity)  // Full-width, centered content
    }
}
```

**No sidebar. No `NavigationSplitView`.** Just a scrollable full-width view with centered content.

### Step 5.2: Create `Views/AgentPolicyCard.swift`

Simplified glanceable card per LAYOUT-SPEC §Agent Card:

```swift
struct AgentPolicyCard: View {
    let agent: TargetApp
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: dot + name + connection badge + Pause Access button
            HStack {
                AgentDot(agent: agent)
                Text(agent.displayName)
                    .font(.headline)
                ConnectionBadge(agent: agent)
                Spacer()
                Button("Pause Access") { store.policy.pauseAgent(agent) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .onHover { hovering in /* turn red on hover */ }
            }

            // Summary lines — NOT per-source lists
            Text("\(sourceCount) of \(totalSources) sources · \(fileCount) files · \(sizeStr)")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("\(domainCount) domains · \(emailCount) emails visible · \(sensitivity)")
                .font(.body)
                .foregroundStyle(.secondary)

            // Actions
            HStack(spacing: 8) {
                Button("Review & Update Access") {
                    store.requestReviewSheet(reason: .explicit(agent))
                }
                .buttonStyle(.borderedProminent)

                Button("View Activity →") { store.openActivityDrawer(agent: agent) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 12))
        .overlay(alignment: .leading) {
            // 3pt colored left border
            Rectangle().fill(agent.color).frame(width: 3)
        }
    }
}
```

**What is NOT in this card**: No per-source ✓/✗ list. No domain counts. No activity feed. No work block status. Those belong in their respective tabs/banner.

### Step 5.3: Empty states

Per LAYOUT-SPEC:
- No agents connected: "No AI agents connected. Manifold will appear here when Claude or Codex connects via MCP."
- Agent connected, no access: "Claude is connected but can't access any files or emails. [Review & Update Access] to get started."

### Validation
- Overview renders full-width with two cards
- Cards show summary lines, not detailed lists
- "Pause Access" toggles state (red on hover)
- Empty states render when appropriate

---

## Phase 6: Files Tab — Sources Mode + File Browser

**Goal**: The primary file access surface. Sidebar-as-mode-switch pattern. Agent Focus segmented. Row tinting. ALL broadening through Review sheet.

### Step 6.1: Create `Views/FilesTabView.swift`

```swift
struct FilesTabView: View {
    @Environment(ManifoldStore.self) var store
    @State private var selectedSource: SourceRecord?
    @State private var agentFocus: AgentFocusMode = .claude

    var body: some View {
        NavigationSplitView {
            FilesSidebar(selectedSource: $selectedSource)
        } detail: {
            if let source = selectedSource {
                FileBrowserView(source: source)
            } else {
                SourcesTableView(agentFocus: $agentFocus)
            }
        }
        .inspector(isPresented: inspectorBinding) {
            FileInspectorView()
        }
    }
}
```

### Step 6.2: Create `Views/FilesSidebar.swift`

Pure navigation. No view toggles. No settings.

```swift
struct FilesSidebar: View {
    @Binding var selectedSource: SourceRecord?
    @Environment(ManifoldStore.self) var store

    var body: some View {
        List(selection: $selectedSource) {
            Section("Sources") {
                // "All Sources" item → deselects, shows SourcesTableView
                // Each source → colored dot showing focused agent's access
            }
            Section("Versions") {
                // Recently Modified, Conflicts, AI-Touched Files
            }
        }
        // Footer: View Activity → link
        .safeAreaInset(edge: .bottom) {
            Button("View Activity →") { ... }
        }
    }
}
```

**Sidebar is the mode switch**: clicking a source shows its file browser. Clicking "All Sources" or deselecting shows the Sources overview table.

### Step 6.3: Create `Views/SourcesTableView.swift`

Use SwiftUI `Table` (not `List` with manual grid). The Table columns change based on `agentFocus`:

```swift
struct SourcesTableView: View {
    @Binding var agentFocus: AgentFocusMode
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                AgentFocusControl(mode: $agentFocus)
                SearchField("Search sources...")
                Button("+ Add Folder...") { ... }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Table
            Table(store.sources) {
                TableColumn("Name") { source in
                    Label(source.displayName, systemImage: "folder")
                }
                TableColumn("Path") { source in Text(source.originalRootPath).foregroundStyle(.secondary) }
                TableColumn("Items") { ... }
                TableColumn("Size") { ... }

                // Conditional columns based on agentFocus
                if agentFocus == .compare {
                    TableColumn("Claude") { source in AccessCheckbox(source: source, agent: .cowork) }
                    TableColumn("Codex") { source in AccessCheckbox(source: source, agent: .codex) }
                } else {
                    TableColumn("Access") { source in AccessCheckbox(source: source, agent: focusedAgent) }
                }
            }
        }
    }
}
```

### Step 6.4: The critical interaction — `AccessCheckbox`

This component implements the **Intentionality Rule**:

```swift
struct AccessCheckbox: View {
    let source: SourceRecord
    let agent: TargetApp
    @Environment(ManifoldStore.self) var store

    private var isIncluded: Bool {
        store.policy.policy(for: agent)?.allowedSourceIDs.contains(source.sourceID) ?? false
    }

    var body: some View {
        Toggle("", isOn: Binding(
            get: { isIncluded },
            set: { newValue in
                if newValue {
                    // BROADENING → open Review sheet, do NOT toggle yet
                    store.requestReviewSheet(reason: .addSource(source, agent))
                } else {
                    // NARROWING → immediate + undo toast
                    Task {
                        await store.policy.updateFileAccess(agent: agent, sourceID: source.sourceID, included: false)
                        store.showUndoToast("Removed \(agent.displayName) access to \(source.displayName)") {
                            Task { await store.policy.updateFileAccess(agent: agent, sourceID: source.sourceID, included: true) }
                        }
                    }
                }
            }
        ))
        .toggleStyle(.checkbox)
        .tint(agent.color)
    }
}
```

> **CRITICAL**: Checking a box does NOT immediately toggle. It opens the Review sheet. The actual state change happens when the user confirms in the sheet. This is the most important interaction in the product.

### Step 6.5: Row tinting

Apply a subtle background tint on checked rows:
```swift
.listRowBackground(
    isIncluded ? agent.color.opacity(0.06) : Color.clear
)
```

Use the animation: `.animation(.easeInOut(duration: 0.2), value: isIncluded)` for tint transitions.

### Step 6.6: File Browser mode

When a source is selected in the sidebar, show the existing `FilesView.swift` file browser adapted with:
- "← Sources" breadcrumb button to deselect
- Source name in toolbar
- File rows show colored dot for AI access (from the focused agent)
- Click row → opens Inspector (version history, diff, restore)

### Validation
- Agent Focus segmented control toggles between Claude/Codex/Compare
- Checking an unchecked source opens Review sheet (does NOT immediately toggle)
- Unchecking a source is immediate with undo toast
- Row tinting appears for checked rows in focused agent's color
- Sidebar click on source → file browser. Click "All Sources" → back to table.

---

## Phase 7: Emails Tab — Domains Mode + Messages

**Goal**: Domain-level access table. Sensitivity in toolbar. Sidebar = pure navigation.

### Step 7.1: Create `Views/EmailsTabView.swift`

Same pattern as Files: `NavigationSplitView` with sidebar selecting mode.

```swift
struct EmailsTabView: View {
    @State private var selectedMailbox: MailboxSelection?  // nil = All Mail = Domains mode
    @State private var agentFocus: AgentFocusMode = .claude

    var body: some View {
        NavigationSplitView {
            EmailsSidebar(selection: $selectedMailbox)
        } detail: {
            if let mailbox = selectedMailbox {
                EmailMessagesView(mailbox: mailbox)
            } else {
                DomainsTableView(agentFocus: $agentFocus)
            }
        }
    }
}
```

### Step 7.2: Modify `Email/Sidebar/EmailSidebar.swift`

**Remove**: Sensitivity pickers, view mode toggle, "Session Email Access" stats.
**Keep**: Accounts tree, Smart Mailboxes, Add Account.
**Add**: "View Activity →" link.

The sidebar is pure navigation. Sensitivity lives in the Domains toolbar.

### Step 7.3: Create `Views/DomainsTableView.swift`

Table with category grouping (Work, Automated, Personal, Hidden by sensitivity):

```swift
struct DomainsTableView: View {
    @Binding var agentFocus: AgentFocusMode
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: Agent Focus + Search + Sensitivity
            HStack {
                AgentFocusControl(mode: $agentFocus)
                SearchField("Search domains...")
                SensitivityPicker(agent: focusedAgent)  // Per focused agent
            }

            // Grouped list/table
            List {
                ForEach(DomainCategory.allCases) { category in
                    Section(category.label) {
                        ForEach(domains(in: category)) { domain in
                            DomainRow(domain: domain, agentFocus: agentFocus)
                        }
                    }
                }
            }

            // Footer: counts
        }
    }
}
```

### Step 7.4: Domain row with updated copy

```swift
struct DomainRow: View {
    let domain: DomainAggregate

    var body: some View {
        HStack {
            // Icon + domain name
            // Email count
            // "+ future mail" inline text (only if checked)
            // Access checkbox (same Intentionality Rule as sources)
        }
    }
}
```

Copy rules from LAYOUT-SPEC §Copy:
- Checked domains show: `"247"` + `"+ future mail"` in green
- Unchecked domains show: `"15"` (just the count, no future indicator)
- Hidden domains: count + reason label ("banking", "health", "2FA"), checkbox disabled

### Step 7.5: Sensitivity picker in toolbar

```swift
struct SensitivityPicker: View {
    let agent: TargetApp
    @Environment(ManifoldStore.self) var store

    var body: some View {
        HStack {
            Text("Sensitivity:")
                .foregroundStyle(.secondary)
            Picker("", selection: sensitivityBinding) {
                Text("Strict").tag(EmailSensitivity.strict)
                Text("Moderate").tag(EmailSensitivity.moderate)
                Text("Open").tag(EmailSensitivity.open)
            }
        }
    }
}
```

**Loosening sensitivity** (stricter → less strict) = broadening → opens Review sheet.
**Tightening sensitivity** = narrowing → immediate + undo toast.

### Step 7.6: Messages mode — hidden email actions

In `Email/ReadingPane/EmailReadingPane.swift`, add for hidden emails:
- "Reveal temporarily" button → creates `TemporaryReveal` (single email, expires at run end)
- "Allow domain" button → opens Review sheet pre-focused on that domain

### Validation
- Domains table shows category groups
- "+ future mail" appears inline on checked domains only
- Sensitivity dropdown is in the toolbar, not the sidebar
- Checking a domain → opens Review sheet
- Hidden domains have disabled checkboxes and reason labels (not opacity)

---

## Phase 8: Review & Update Access Sheet

**Goal**: Full-height attached sheet. The product's commitment surface. Opens on EVERY broadening action.

### Step 8.1: Create `Views/ReviewAccessSheet.swift`

```swift
struct ReviewAccessSheet: View {
    @Environment(ManifoldStore.self) var store
    @State private var sheetTab: SheetTab = .files
    @State private var pendingChanges: PendingPolicyChanges  // what the user is proposing

    enum SheetTab { case files, emails }

    var body: some View {
        VStack(spacing: 0) {
            // Header: "Review & Update Access" + agent switcher
            sheetHeader

            // Body: scrollable
            ScrollView {
                // "What's Changing" section — green tinted
                whatsChangingSection

                // Files | Emails tab bar
                Picker("", selection: $sheetTab) {
                    Text("Files").tag(SheetTab.files)
                    Text("Emails").tag(SheetTab.emails)
                }
                .pickerStyle(.segmented)

                // Tab content
                switch sheetTab {
                case .files: filesContent
                case .emails: emailsContent
                }

                // Advanced disclosure
                DisclosureGroup("Advanced") { ... }
            }

            // Sticky footer
            sheetFooter
        }
        .presentationDetents([.large])  // Full-height
    }
}
```

### Step 8.2: "What's Changing" section

Light green tinted background. Shows the specific proposed additions:
```
+ Adding 📁 assets (22 files, 156 MB)
```

or:
```
+ Adding @company.com to Claude (247 archived now, + future mail)
```

Existing grants labeled "(current)". New additions labeled "new ✦".

### Step 8.3: Dynamic primary button label

```swift
var primaryButtonLabel: String {
    switch reason {
    case .firstGrant: return "Allow Access"
    case .addSource, .addDomain, .loosenSensitivity: return "Update Access"
    case .startWorkBlock: return "Start Tracked Work Block"
    case .copyPolicy: return "Copy Access"
    }
}
```

### Step 8.4: Two CTAs in footer

- "Update Access" (primary, `.borderedProminent`)
- "Start Tracked Work Block" (secondary, `.bordered`)
- "Cancel" (`.plain`)

### Step 8.5: Wire triggers from ALL broadening actions

In `ManifoldStore`, add:
```swift
enum ReviewSheetReason {
    case addSource(SourceRecord, TargetApp)
    case addDomain(String, TargetApp)
    case loosenSensitivity(TargetApp, from: EmailSensitivity, to: EmailSensitivity)
    case startWorkBlock(TargetApp)
    case copyPolicy(from: TargetApp, to: TargetApp)
    case explicit(TargetApp)
    case firstGrant(TargetApp)
}

var pendingReviewReason: ReviewSheetReason?
var showReviewSheet: Bool { pendingReviewReason != nil }

func requestReviewSheet(reason: ReviewSheetReason) {
    pendingReviewReason = reason
}
```

### Validation
- Sheet opens on EVERY broadening action (source check, domain check, sensitivity loosen)
- Sheet does NOT open for narrowing actions
- Changes only apply when user confirms
- "What's Changing" section highlights the specific proposed change
- Sheet dismisses on Cancel with no state change

---

## Phase 9: Tracked Work Blocks

**Goal**: Opt-in snapshot/promote lifecycle with global banner.

### Step 9.1: Wire `WorkBlockModel` to stores

Connect to `MaterializationEngine`, `SnapshotStore`, `PromoteEngine`.

### Step 9.2: Start work block flow

1. User clicks "Start Tracked Work Block" (Overview or Review sheet)
2. Review sheet opens with "Start Tracked Work Block" as primary CTA
3. User confirms scope → `WorkBlockModel.startBlock()`
4. MaterializationEngine creates workspace, SnapshotStore takes baseline
5. Work Block Banner appears (animated with `spring(response: 0.4, dampingFraction: 0.85)`)

### Step 9.3: Create `Views/ReviewChangesSheet.swift`

For "Finish & Review":
1. `PromoteEngine.dryRun()` → shows preview
2. Categories: Applied, Conflicts, New, Skipped
3. Per-file approve/rollback toggles
4. "Promote" button → `PromoteEngine.promote()`
5. Work block ends. Banner disappears. Standing access continues.

### Step 9.4: Banner actions

- "Finish & Review" → `PromoteEngine.dryRun()` → ReviewChangesSheet
- "Pause Access" → `PolicyModel.pauseAgent()` + `WorkBlockModel.pauseBlock()`
- "Stop Now" → confirmation alert → discard workspace → remove banner

### Validation
- Work block can be started, files are materialized
- Banner visible on ALL tabs during active block
- "Finish & Review" shows diff and promotes correctly
- "Stop Now" requires confirmation, then discards

---

## Phase 10: Activity Drawer + Cleanup

**Goal**: Activity as right drawer. Delete all session artifacts. Final polish.

### Step 10.1: Create `Views/ActivityDrawer.swift`

Wrap existing `ActivityView` internals in a right-side drawer. Use `.inspector()` modifier or a custom trailing panel — check `swiftui-pro` skill for recommended pattern.

- Agent filter (Claude / Codex / All)
- Chronological event timeline
- Accessible from: Overview "View Activity →", sidebar links, ⌘⇧A

### Step 10.2: Delete session artifacts

Only after everything else works:
- Delete `SessionView.swift`
- Delete `PresetPickerView.swift`
- Delete `Models/SessionModel.swift`
- Delete `Views/Dashboard/` directory (replaced by `OverviewView`)
- Remove `HistoryView.swift` as a standalone view (contents live in ActivityDrawer)
- Remove `SidebarItem` enum and all references

### Step 10.3: Polish pass

- **Animations**: Verify all transitions match LAYOUT-SPEC §Animation Language table
- **Accessibility**: VoiceOver labels on all interactive elements, 44pt touch targets on checkboxes
- **Material discipline**: Liquid Glass on top bar + sheet chrome + inspector frame only. Stable opaque for data rows.
- **Dark mode**: Test all states in both light and dark. Hidden rows must pass WCAG AA contrast.
- **Copy audit**: Walk through LAYOUT-SPEC §Copy/Label Guide. Replace every old label:
  - "Home" → "Overview"
  - "Pause" → "Pause Access"
  - "Review Access..." → "Review & Update Access"
  - "Start Work Block..." → "Start Tracked Work Block"
  - "Archived" column → "Emails" count
  - "Future: Included/Excluded" → "+ future mail" inline text or nothing

### Step 10.4: Empty states

Implement all empty states from LAYOUT-SPEC:
- No agents connected (Overview)
- Agent connected, no access (Overview)
- No sources added (Files)
- No email accounts (Emails)

### Validation
- Full v4.1 flow end-to-end: Overview → check source → Review sheet → confirm → row tints → switch to Emails → check domain → Review sheet → confirm
- No session artifacts remain in code
- `swift test` passes
- App builds with zero warnings
- VoiceOver navigates all interactive elements

---

## Keyboard Shortcuts Reference

Wire these in `ManifoldApp.swift` via `.keyboardShortcut()` or `.onKeyPress()`:

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| ⌘1 | Switch to Overview | `store.selectedTab = .overview` |
| ⌘2 | Switch to Files | `store.selectedTab = .files` |
| ⌘3 | Switch to Emails | `store.selectedTab = .emails` |
| ⌘K | Command palette | `commands.isPresented = true` |
| ⌘⇧R | Review & Update Access | `store.requestReviewSheet(reason: .explicit(focusedAgent))` |
| ⌘⇧W | Toggle Work Block | Start if none active, Finish & Review if active |
| ⌘⇧P | Pause/Resume access | Toggle `isPaused` on focused agent |
| ⌘I | Toggle Inspector | `store.inspectedFilePath = nil` or select |
| ⌘⇧A | Toggle Activity drawer | `store.showActivityDrawer.toggle()` |
| Escape | Close inspector/sheet/drawer | Dismiss topmost overlay |
| Tab | Cycle agent focus | Claude → Codex → Compare (in Files/Emails only) |

---

## Animation Curves Reference

Use these SwiftUI animations (from LAYOUT-SPEC §Animation Language):

```swift
// Tab switch
.animation(.easeInOut(duration: 0.2), value: selectedTab)

// Sidebar content change
.animation(.easeInOut(duration: 0.15), value: selectedSource)

// Checkbox state
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isIncluded)

// Row tint
.animation(.easeInOut(duration: 0.2), value: isIncluded)

// Inspector
.animation(.spring(response: 0.35, dampingFraction: 0.85), value: showInspector)

// Sheet present
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSheet)

// Toast
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: showToast)
.animation(.easeOut(duration: 0.15), value: !showToast)

// Work Block Banner
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasActiveBlock)

// Agent focus switch
.animation(.easeInOut(duration: 0.15), value: agentFocus)
```

---

## Testing Strategy

Each phase should have tests before moving to the next:

| Phase | What to test |
|-------|-------------|
| 0 | PolicyStore CRUD, WorkBlockStore CRUD, migration runs |
| 1 | Bridge resolves standing access, paused denies, work block routes |
| 2 | Tab switching, keyboard shortcuts |
| 3 | PolicyModel loads and updates, DomainModel computes aggregates |
| 4-5 | Overview renders, agent cards show correct summaries |
| 6 | Source checkbox broadening → sheet, narrowing → immediate, row tinting |
| 7 | Domain checkbox same, sensitivity broadening → sheet, category grouping |
| 8 | Sheet opens on all broadening triggers, changes only on confirm |
| 9 | Work block start/finish/stop, promote works, banner on all tabs |
| 10 | No session references compile, full flow E2E |

---

## Reference Documents

| Document | Use for |
|----------|---------|
| `design/LAYOUT-SPEC-v4.md` | **Source of truth** for what every screen looks like, all copy, all rules |
| `design/manifold-wireframe-v4.html` | **Visual reference only** — open in browser to see layout, do NOT port HTML |
| `design/navigation-flows-v4.mermaid` | Navigation graph — what connects to what |
| `design/IMPLEMENTATION-PLAN-v4.md` | Detailed file-by-file audit (for reference, this plan supersedes it) |
| `design/DESIGN-CRITIQUE-v4.md` | The 8-point critique — explains WHY each design decision was made |
| `design/CLAUDE-CODE-SETTINGS-SETUP-PLAN.md` | **Phases 11–14**: Settings, Setup Assistant, connection sheets, email setup |
| `swiftui-pro` skill | **INVOKE BEFORE WRITING CODE** — has macOS 26 Liquid Glass patterns |
