# Manifold v4.1 — Settings, Setup Assistant & Connection Sheets

> **Companion to**: `CLAUDE-CODE-IMPLEMENTATION-PLAN.md` (phases 0–10). This document covers phases 11–14: Settings window rewrite, first-run Setup Assistant, per-agent connection sheets, and email account setup.
>
> **Required skill**: Invoke `swiftui-pro` before writing any SwiftUI code. It has macOS 26 Liquid Glass patterns, `.sheet()` best practices, and Form/Settings conventions.
>
> **Design authority**: `LAYOUT-SPEC-v4.md` remains the source of truth. This plan fills in the Settings and onboarding surfaces that the layout spec intentionally defers to the Settings window (see §Feature→Location map: "Storage / MCP Status → Settings window, NOT in Overview").

---

## Design Principles — The LoveFrom Rules

Every view in this plan must follow these eight rules. They are not style suggestions — they are hard constraints. If a view violates any of them, it is wrong and must be fixed before moving on.

| # | Rule | What it means in practice |
|---|------|--------------------------|
| 1 | No carousels, no horizontal paging | Every screen is one complete thought. No swiping, no "next slide." |
| 2 | One sentence per screen | Each screen has exactly one headline sentence that tells you what it does. Supporting text goes below in `.secondary`. |
| 3 | Big status, small explanation | The checkmark/spinner/warning is 36pt+. The explanation is `.callout` or `.caption`. Status dominates. |
| 4 | One primary action per screen | One `.borderedProminent` button. Everything else is `.bordered`, `.plain`, or a skip link. |
| 5 | Technical detail behind disclosure | Paths, config files, CLI commands go inside `DisclosureGroup`. Never on the main surface. |
| 6 | Return state re-check | When a sheet reappears or a Settings pane loads, re-run all health checks. Never show stale status. |
| 7 | Liquid Glass only in chrome | `.glassEffect()` on the toolbar, top bar, sheet frame. Content areas are stable opaque. |
| 8 | Write like Apple | Short. Declarative. No exclamation marks. "Connected" not "Successfully connected!" |

---

## Current State Audit

### Files to REWRITE (not patch)

| File | Current | Target |
|------|---------|--------|
| `Views/SetupView.swift` | 5-tab Settings (General, Connection, Email, Storage, About) | 4-tab Settings (General, AI Apps, Mail, Storage) |
| `Views/OnboardingView.swift` | 6-step progress-bar wizard (welcome → claudeCheck → install → source → email → done) | 4-screen Setup Assistant (Welcome → Connect AI Apps → Add Your Data → Review & Finish) |
| `Models/SetupModel.swift` | Flat booleans: `mcpInstalled`, `claudeDesktopConfigured`, `codexConfigured` | Structured per-agent health: `IntegrationHealthModel` with `AgentConnectionState` |

### Files to CREATE

| File | Purpose |
|------|---------|
| `Views/Settings/SettingsView.swift` | New Settings window root (replaces SetupView.swift) |
| `Views/Settings/GeneralSettingsPane.swift` | General tab: launch at login, notifications |
| `Views/Settings/AIAppsSettingsPane.swift` | AI Apps tab: two agent cards, repair surface |
| `Views/Settings/MailSettingsPane.swift` | Mail tab: accounts list, add/remove, sync settings |
| `Views/Settings/StorageSettingsPane.swift` | Storage tab: location, size, maintenance |
| `Views/Setup/SetupAssistantView.swift` | First-run 4-screen assistant |
| `Views/Setup/ConnectClaudeSheet.swift` | Sheet: 3 live checks for Claude Desktop + Extension |
| `Views/Setup/ConnectCodexSheet.swift` | Sheet: 3 live checks for Codex CLI |
| `Views/Setup/AddMailAccountSheet.swift` | Sheet: provider-first email setup flow |
| `Models/IntegrationHealthModel.swift` | Per-agent connection state machine + polling |
| `Models/AgentConnectionState.swift` | State enum + live-check logic per agent |
| `Models/MailSetupModel.swift` | OAuth flow + IMAP validation state |
| `Views/EmptyStates/NoAgentsConnectedView.swift` | Overview empty state: no agents → show connect cards |
| `Views/EmptyStates/NoEmailAccountsView.swift` | Emails empty state: no accounts → prompt setup |
| `Views/EmptyStates/NoAccessGrantedView.swift` | Overview empty state: connected but no access |

### Files to DELETE

| File | Why |
|------|-----|
| `Views/SetupView.swift` | Replaced by `Views/Settings/SettingsView.swift` |
| `Views/OnboardingView.swift` | Replaced by `Views/Setup/SetupAssistantView.swift` |

---

## Phase 11: IntegrationHealthModel — Per-Agent Connection State Machine

**Goal**: Replace flat booleans in `SetupModel` with a structured, pollable health model. No UI changes yet.

### Step 11.1: Create `Models/AgentConnectionState.swift`

```swift
import Foundation

/// Connection health for a single AI agent.
public enum AgentConnectionStatus: String, Sendable {
    case unknown        // Not yet checked
    case checking       // Active health check in progress
    case notInstalled   // App/CLI not found on disk
    case installed      // App/CLI found but not configured for Manifold
    case configured     // Config exists but connection not verified
    case connected      // Live MCP handshake succeeded
    case error          // Check failed with an error
}

@Observable
@MainActor
public final class AgentConnectionState: Identifiable {
    public let id: TargetApp

    // Claude-specific checks
    var appInstalled: AgentConnectionStatus = .unknown      // Claude Desktop.app exists
    var extensionInstalled: AgentConnectionStatus = .unknown // .mcpb extension registered
    var connectionVerified: AgentConnectionStatus = .unknown // MCP handshake

    // Codex-specific checks
    var cliInstalled: AgentConnectionStatus = .unknown       // `codex` binary in PATH
    var cliSignedIn: AgentConnectionStatus = .unknown        // `codex` auth status
    var mcpAdded: AgentConnectionStatus = .unknown           // `manifold` in codex MCP list

    var errorDetail: String?

    /// Overall rollup for the agent card badge.
    var overallStatus: AgentConnectionStatus {
        switch id {
        case .cowork:
            if connectionVerified == .connected { return .connected }
            if [appInstalled, extensionInstalled, connectionVerified].contains(.error) { return .error }
            if appInstalled == .notInstalled { return .notInstalled }
            return .configured
        case .codex:
            if mcpAdded == .connected { return .connected }
            if [cliInstalled, cliSignedIn, mcpAdded].contains(.error) { return .error }
            if cliInstalled == .notInstalled { return .notInstalled }
            return .configured
        }
    }

    init(agent: TargetApp) { self.id = agent }
}
```

### Step 11.2: Create `Models/IntegrationHealthModel.swift`

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "health")

@Observable
@MainActor
final class IntegrationHealthModel {
    var claude = AgentConnectionState(agent: .cowork)
    var codex = AgentConnectionState(agent: .codex)

    func state(for agent: TargetApp) -> AgentConnectionState {
        switch agent {
        case .cowork: return claude
        case .codex: return codex
        }
    }

    // MARK: - Claude checks

    func checkClaude() async {
        claude.appInstalled = .checking
        claude.extensionInstalled = .checking
        claude.connectionVerified = .checking

        // 1. Claude Desktop installed?
        let claudeAppPath = "/Applications/Claude.app"
        let altPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude.app").path
        claude.appInstalled = FileManager.default.fileExists(atPath: claudeAppPath)
            || FileManager.default.fileExists(atPath: altPath)
            ? .installed : .notInstalled

        // 2. Desktop Extension registered?
        //    Check for manifold entry in claude_desktop_config.json
        //    OR check the Extensions directory for manifold.mcpb
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = json["mcpServers"] as? [String: Any],
           servers.keys.contains(where: { $0.lowercased().contains("manifold") }) {
            claude.extensionInstalled = .installed
        } else {
            claude.extensionInstalled = .notInstalled
        }

        // 3. Live connection verification
        //    Attempt to reach ManifoldMCP via its expected STDIO/socket.
        //    For now: check if the MCP binary exists and config points to it.
        let binaryExists = FileManager.default.fileExists(atPath: ManifoldStore.mcpBinaryPath)
        claude.connectionVerified = (claude.extensionInstalled == .installed && binaryExists)
            ? .connected : .configured
    }

    // MARK: - Codex checks

    func checkCodex() async {
        codex.cliInstalled = .checking
        codex.cliSignedIn = .checking
        codex.mcpAdded = .checking

        // 1. Codex CLI installed?
        let codexPaths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        let homeCodex = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/codex").path
        let found = (codexPaths + [homeCodex]).contains { FileManager.default.fileExists(atPath: $0) }
        codex.cliInstalled = found ? .installed : .notInstalled

        guard found else {
            codex.cliSignedIn = .notInstalled
            codex.mcpAdded = .notInstalled
            return
        }

        // 2. Signed in?
        //    Check ~/.codex/auth.json or similar auth artifact
        let authPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json").path
        codex.cliSignedIn = FileManager.default.fileExists(atPath: authPath)
            ? .installed : .notInstalled

        // 3. Manifold MCP added?
        //    Check ~/.codex/config.toml for manifold entry
        let tomlPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
        if let contents = try? String(contentsOfFile: tomlPath, encoding: .utf8),
           contents.lowercased().contains("manifold") {
            codex.mcpAdded = .connected
        } else {
            codex.mcpAdded = .notInstalled
        }
    }

    /// Run all checks. Call on Settings open, sheet appear, and Setup Assistant load.
    func checkAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkClaude() }
            group.addTask { await self.checkCodex() }
        }
    }
}
```

### Step 11.3: Wire into ManifoldStore

In `ManifoldStore.swift`, replace the flat setup booleans:

```swift
// REMOVE these from ManifoldStore (they currently delegate to SetupModel):
// var mcpInstalled, claudeDesktopConfigured, codexConfigured

// ADD:
let integrationHealth = IntegrationHealthModel()

// Computed compatibility shims (for existing code that reads the old booleans):
var mcpInstalled: Bool { integrationHealth.claude.connectionVerified == .connected }
var claudeDesktopConfigured: Bool { integrationHealth.claude.extensionInstalled == .installed }
var codexConfigured: Bool { integrationHealth.codex.mcpAdded == .connected }
```

### Step 11.4: Migrate SetupModel

`SetupModel.swift` keeps ONLY user preferences:
- `hasCompletedOnboarding`
- `launchAtLogin`
- `notifyOnSessionEnd` / `notifyOnAccessDenied`
- `sessionNotesMode`

Remove: `mcpInstalled`, `installError`, `claudeDesktopConfigured`, `codexConfigured`, `checkMCPInstalled()`, `checkAgentConfigs()`, `installMCP()`. The install logic moves to `IntegrationHealthModel` or a dedicated `MCPInstaller` utility.

### Validation
- `IntegrationHealthModel.checkAll()` runs and populates all states
- `ManifoldStore.mcpInstalled` shim still works for any remaining callers
- `SetupModel` is slim — preferences only
- No compilation errors

---

## Phase 12: Settings Window — 4 Tabs

**Goal**: Rewrite the Settings window. Four tabs: General, AI Apps, Mail, Storage. Settings is a maintenance surface — it shows status and allows repair. It is NOT the control plane for access (that's the Review sheet).

### Step 12.1: Create `Views/Settings/SettingsView.swift`

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
        .frame(width: 520, height: 460)
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

### Step 12.2: Create `Views/Settings/GeneralSettingsPane.swift`

Minimal. Matches the old General tab but drops the accent color note (not useful).

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

### Step 12.3: Create `Views/Settings/AIAppsSettingsPane.swift`

This is the most important Settings pane. Two large cards — one per agent — each showing 3 health checks with live status. This is the repair surface.

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

### Step 12.4: `AgentSettingsCard` component

```swift
struct AgentSettingsCard: View {
    let agent: TargetApp
    let state: AgentConnectionState
    let onSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: agent name + overall status badge
            HStack {
                Circle()
                    .fill(agent.color)
                    .frame(width: 8, height: 8)
                Text(agent.displayName)
                    .font(.headline)
                Spacer()
                OverallStatusBadge(status: state.overallStatus)
            }

            // 3 check rows (different per agent)
            switch agent {
            case .cowork:
                CheckRow("App installed", status: state.appInstalled)
                CheckRow("Extension installed", status: state.extensionInstalled)
                CheckRow("Connection verified", status: state.connectionVerified)
            case .codex:
                CheckRow("CLI installed", status: state.cliInstalled)
                CheckRow("Signed in", status: state.cliSignedIn)
                CheckRow("Manifold added", status: state.mcpAdded)
            }

            // Action button — adapts label to state
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

### Step 12.5: `CheckRow` component

```swift
/// Single health-check row: icon + label + optional detail behind disclosure.
struct CheckRow: View {
    let label: String
    let status: AgentConnectionStatus
    var detail: String?

    init(_ label: String, status: AgentConnectionStatus, detail: String? = nil) {
        self.label = label
        self.status = status
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 16)
            Text(label)
                .font(.callout)
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
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .notInstalled:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unknown, .configured:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
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

### Step 12.6: Create `Views/Settings/MailSettingsPane.swift`

Port the email accounts list from the old `EmailBackupTab`. Key changes:
- Rename tab from "Email" to "Mail" (Apple convention)
- Keep: account list, sync toggles, add/remove, storage stats
- Add: opens `AddMailAccountSheet` instead of `EmailAccountSetupView`
- The existing email account CRUD code is fine — keep it

```swift
struct MailSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showAddAccount = false

    var body: some View {
        Form {
            Section("Accounts") {
                // Same ForEach as old EmailBackupTab — account list with sync toggles
                // Replace: .sheet opens AddMailAccountSheet (new)
            }
            Section("Storage") {
                // Same as old EmailBackupTab storage section
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddAccount) {
            AddMailAccountSheet()
        }
        .task { await store.emailAccounts.loadAccounts() }
    }
}
```

### Step 12.7: Create `Views/Settings/StorageSettingsPane.swift`

Port from old `StorageTab` almost verbatim. Only change: drop the About content (Manifold name, version, bundle ID). Version info moves to the app's standard About window (SwiftUI provides this automatically via `@main` App).

### Step 12.8: Delete old files

- Delete `Views/SetupView.swift`
- Delete `AboutTab` (its content is gone; version shows in the standard macOS About window)
- Update any `SetupView()` references to `SettingsView()`

### Validation
- Settings opens with ⌘, and shows 4 tabs
- AI Apps tab shows two agent cards with live status checks
- Status re-checks on every tab switch / window reappear (Rule 6)
- "Set Up" button opens the appropriate connection sheet
- Mail tab lists accounts, add button opens new sheet
- Storage tab shows stats and maintenance actions
- No About tab exists

---

## Phase 13: Setup Assistant — First Run

**Goal**: 4-screen Setup Assistant shown once on first launch. Replaces the 6-step OnboardingView. Each screen follows the LoveFrom rules: one sentence, one primary action, big status.

### Design: The Four Screens

| Screen | Headline | Primary Action | Skip? |
|--------|----------|---------------|-------|
| 1. Welcome | "Manifold controls what AI agents see on your Mac." | Get Started | No |
| 2. Connect AI Apps | "Connect Claude or Codex." | (Set Up button per card) | Yes — "Skip, I'll do this later" |
| 3. Add Your Data | "Choose what to share." | (Add Folder / Add Email Account) | Yes — "Skip for now" |
| 4. Review & Finish | "You're ready." | Open Manifold | No |

### Step 13.1: Create `Views/Setup/SetupAssistantView.swift`

```swift
import SwiftUI
import ManifoldKit

struct SetupAssistantView: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    @State private var screen: SetupScreen = .welcome

    enum SetupScreen: Int, CaseIterable {
        case welcome = 0
        case connectApps = 1
        case addData = 2
        case reviewFinish = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots (not a bar — 4 dots, filled up to current screen)
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

            // Screen content
            Group {
                switch screen {
                case .welcome: WelcomeScreen(advance: advance)
                case .connectApps: ConnectAppsScreen(advance: advance, skip: advance)
                case .addData: AddDataScreen(advance: advance, skip: advance)
                case .reviewFinish: ReviewFinishScreen(finish: finish)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Back button (screens 1–2 only)
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
            if let next = SetupScreen(rawValue: screen.rawValue + 1) {
                screen = next
            }
        }
    }

    private func finish() {
        store.hasCompletedOnboarding = true
        dismiss()
    }
}
```

### Step 13.2: Screen 1 — Welcome

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

            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 48)
    }
}
```

One sentence. One primary action. No feature list carousel.

### Step 13.3: Screen 2 — Connect AI Apps

Two cards, same `AgentSettingsCard` from Phase 12 but adapted for the assistant context. Each card shows live checks and a "Set Up" button that opens the appropriate connection sheet.

```swift
private struct ConnectAppsScreen: View {
    let advance: () -> Void
    let skip: () -> Void
    @Environment(ManifoldStore.self) var store
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect Claude or Codex.")
                .font(.title2.weight(.semibold))

            Text("Manifold works with either or both. You can always add more later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SetupAgentCard(
                    agent: .cowork,
                    state: store.integrationHealth.claude,
                    onSetup: { showClaudeSheet = true }
                )
                SetupAgentCard(
                    agent: .codex,
                    state: store.integrationHealth.codex,
                    onSetup: { showCodexSheet = true }
                )
            }
            .frame(maxWidth: 400)

            // If at least one agent is connected, show Continue
            if store.integrationHealth.claude.overallStatus == .connected
                || store.integrationHealth.codex.overallStatus == .connected {
                Button("Continue") { advance() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Skip, I'll do this later") { skip() }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 48)
        .task { await store.integrationHealth.checkAll() }
        .sheet(isPresented: $showClaudeSheet) {
            ConnectClaudeSheet()
        }
        .sheet(isPresented: $showCodexSheet) {
            ConnectCodexSheet()
        }
    }
}
```

`SetupAgentCard` is a compact version of `AgentSettingsCard` — same 3 check rows, same "Set Up" button, but in a card layout appropriate for the assistant context.

### Step 13.4: Screen 3 — Add Your Data

Two sections: folders and email. Each has an add button and a list of what's been added so far.

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

                    if !store.approvedSources.isEmpty {
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
                    }

                    Button("Add Folder…") { store.addSourceFromPicker() }
                        .controlSize(.small)
                }

                Divider()

                // Email section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Email", systemImage: "envelope")
                        .font(.callout.weight(.medium))

                    if !store.emailAccounts.accounts.isEmpty {
                        ForEach(store.emailAccounts.accounts) { account in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .imageScale(.small)
                                Text(account.displayName)
                                    .font(.caption)
                            }
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

### Step 13.5: Screen 4 — Review & Finish

Summary of what was configured. Big checkmark. One button.

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
                SummaryRow(
                    "AI Apps",
                    status: agentSummary,
                    done: store.integrationHealth.claude.overallStatus == .connected
                        || store.integrationHealth.codex.overallStatus == .connected
                )
                SummaryRow(
                    "Folders",
                    status: store.approvedSources.isEmpty
                        ? "None added yet"
                        : "\(store.approvedSources.count) folder\(store.approvedSources.count == 1 ? "" : "s")",
                    done: !store.approvedSources.isEmpty
                )
                SummaryRow(
                    "Email",
                    status: store.emailAccounts.accounts.isEmpty
                        ? "No accounts"
                        : "\(store.emailAccounts.accounts.count) account\(store.emailAccounts.accounts.count == 1 ? "" : "s")",
                    done: !store.emailAccounts.accounts.isEmpty
                )
            }
            .frame(maxWidth: 360)

            Text("You can change all of this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Open Manifold") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, 48)
    }

    private var agentSummary: String {
        let agents = [
            store.integrationHealth.claude.overallStatus == .connected ? "Claude" : nil,
            store.integrationHealth.codex.overallStatus == .connected ? "Codex" : nil
        ].compactMap { $0 }
        return agents.isEmpty ? "Not connected" : agents.joined(separator: " and ")
    }
}
```

### Step 13.6: Wire into app launch

In `ManifoldApp.swift`, replace the existing onboarding presentation:

```swift
.sheet(isPresented: Binding(
    get: { !store.hasCompletedOnboarding },
    set: { if !$0 { store.hasCompletedOnboarding = true } }
)) {
    SetupAssistantView()
}
```

### Step 13.7: Delete `Views/OnboardingView.swift`

It is fully replaced.

### Validation
- First launch shows the Setup Assistant (4 screens, progress dots)
- Each screen has exactly one headline sentence
- "Get Started" is the only primary button on Welcome
- Connection sheets open from Screen 2 cards
- Screen 3 allows adding folders and email accounts
- Screen 4 shows summary, "Open Manifold" dismisses and sets `hasCompletedOnboarding`
- Subsequent launches skip the assistant
- Back button works on screens 1–2

---

## Phase 14: Connection Sheets — Claude, Codex, Email

**Goal**: Three modal sheets that handle the actual integration setup. Each follows the same pattern: vertical checklist with live status, one primary action, technical detail behind disclosure.

### Step 14.1: Create `Views/Setup/ConnectClaudeSheet.swift`

Three live checks:
1. **Claude Desktop installed** — check `/Applications/Claude.app`
2. **Manifold extension installed** — Claude Desktop Extension (.mcpb)
3. **Connection verified** — MCP handshake

```swift
struct ConnectClaudeSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Circle()
                    .fill(TargetApp.cowork.color)
                    .frame(width: 12, height: 12)
                Text("Connect Claude")
                    .font(.title3.weight(.semibold))
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                // Check 1: App installed
                LiveCheckRow(
                    label: "Claude Desktop installed",
                    status: store.integrationHealth.claude.appInstalled,
                    action: {
                        // Open download page
                        if let url = URL(string: "https://claude.ai/download") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    actionLabel: "Download"
                )

                // Check 2: Extension installed
                LiveCheckRow(
                    label: "Manifold extension installed",
                    status: store.integrationHealth.claude.extensionInstalled,
                    action: {
                        // Install the .mcpb Desktop Extension
                        store.installClaudeExtension()
                    },
                    actionLabel: "Install Extension"
                )

                // Check 3: Connection verified
                LiveCheckRow(
                    label: "Connection verified",
                    status: store.integrationHealth.claude.connectionVerified,
                    action: {
                        Task { await store.integrationHealth.checkClaude() }
                    },
                    actionLabel: "Retry"
                )

                // Technical detail behind disclosure (Rule 5)
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                        DetailLine("Config", value: "~/Library/Application Support/Claude/claude_desktop_config.json")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            Spacer()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Check Again") {
                    Task { await store.integrationHealth.checkClaude() }
                }
                .buttonStyle(.bordered)

                if store.integrationHealth.claude.overallStatus == .connected {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .task { await store.integrationHealth.checkClaude() }  // Rule 6: check on appear
    }
}
```

**Claude Desktop Extension install flow**:

```swift
// In ManifoldStore or a dedicated MCPInstaller:
func installClaudeExtension() {
    // 1. Ensure the MCP binary is in place
    // 2. Use mcpb pack to create the .mcpb bundle (if shipping unbundled)
    //    OR copy the pre-built .mcpb from the app bundle
    // 3. Open the .mcpb file — Claude Desktop handles registration
    //
    // For development: fall back to writing claude_desktop_config.json directly
    //    (same as current installMCP() logic)
    //
    // The .mcpb is the preferred path because it's one-click and
    // doesn't require the user to restart Claude Desktop.
}
```

> **Critical**: Do NOT frame this as "paste JSON config." The user should never see a config file. The `.mcpb` extension install or the `installMCP()` automation handles everything. The config path only appears behind the disclosure group for debugging.

### Step 14.2: Create `Views/Setup/ConnectCodexSheet.swift`

Three live checks:
1. **Codex installed** — check PATH for `codex` binary
2. **Signed in** — check auth artifact
3. **Manifold added** — check `~/.codex/config.toml`

```swift
struct ConnectCodexSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Circle()
                    .fill(TargetApp.codex.color)
                    .frame(width: 12, height: 12)
                Text("Connect Codex")
                    .font(.title3.weight(.semibold))
            }
            .padding(.top, 24)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                // Check 1: CLI installed
                LiveCheckRow(
                    label: "Codex installed",
                    status: store.integrationHealth.codex.cliInstalled,
                    action: {
                        // Open Codex install page or run brew install
                        if let url = URL(string: "https://github.com/openai/codex") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    actionLabel: "Install"
                )

                // Check 2: Signed in
                LiveCheckRow(
                    label: "Signed in",
                    status: store.integrationHealth.codex.cliSignedIn,
                    action: {
                        // Open terminal to run `codex auth login`
                        // or launch codex directly
                    },
                    actionLabel: "Sign In"
                )

                // Check 3: Manifold MCP added
                LiveCheckRow(
                    label: "Manifold added",
                    status: store.integrationHealth.codex.mcpAdded,
                    action: {
                        store.addManifoldToCodex()
                    },
                    actionLabel: "Add to Codex"
                )

                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        DetailLine("Binary", value: ManifoldStore.mcpBinaryPath)
                        DetailLine("Config", value: "~/.codex/config.toml")
                        DetailLine("Command", value: "codex mcp add manifold -- \(ManifoldStore.mcpBinaryPath)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Check Again") {
                    Task { await store.integrationHealth.checkCodex() }
                }
                .buttonStyle(.bordered)

                if store.integrationHealth.codex.overallStatus == .connected {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
        .task { await store.integrationHealth.checkCodex() }
    }
}
```

**Codex MCP add automation**:

```swift
// In ManifoldStore:
func addManifoldToCodex() {
    // Run: codex mcp add manifold -- /path/to/manifold-mcp
    // This writes to ~/.codex/config.toml automatically.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["codex", "mcp", "add", "manifold", "--", Self.mcpBinaryPath]
    do {
        try process.run()
        process.waitUntilExit()
        Task { await integrationHealth.checkCodex() }
    } catch {
        integrationHealth.codex.errorDetail = error.localizedDescription
    }
}
```

### Step 14.3: `LiveCheckRow` reusable component

```swift
/// A health check row with live status and an action button when the check fails.
struct LiveCheckRow: View {
    let label: String
    let status: AgentConnectionStatus
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack(spacing: 12) {
            // Big status icon (Rule 3)
            statusIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                Text(status.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action button only when check fails
            if status == .notInstalled || status == .error {
                Button(actionLabel, action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .connected, .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .notInstalled:
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        case .unknown, .configured:
            Image(systemName: "circle.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Step 14.4: Create `Views/Setup/AddMailAccountSheet.swift`

Provider-first flow. Three providers as large tappable cards, then OAuth or IMAP config.

```swift
struct AddMailAccountSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss

    @State private var phase: MailSetupPhase = .chooseProvider

    enum MailSetupPhase {
        case chooseProvider
        case authenticate(EmailProvider)
        case importSettings(EmailProvider)
        case startingProtection
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(headerText)
                .font(.title3.weight(.semibold))
                .padding(.top, 24)

            Spacer()

            Group {
                switch phase {
                case .chooseProvider:
                    providerPicker
                case .authenticate(let provider):
                    authenticateView(provider: provider)
                case .importSettings(let provider):
                    importSettingsView(provider: provider)
                case .startingProtection:
                    startingProtectionView
                case .done:
                    doneView
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Footer
            HStack {
                if phase != .done {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(20)
        }
        .frame(width: 460, height: 440)
    }

    private var headerText: String {
        switch phase {
        case .chooseProvider: return "Add email account"
        case .authenticate: return "Sign in"
        case .importSettings: return "Import settings"
        case .startingProtection: return "Starting protection"
        case .done: return "Account added"
        }
    }

    // MARK: - Phase 1: Choose Provider

    private var providerPicker: some View {
        VStack(spacing: 12) {
            Text("Choose your email provider.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ProviderButton(
                    name: "Google",
                    icon: "envelope.fill",
                    color: .red,
                    subtitle: "Gmail, Google Workspace"
                ) {
                    withAnimation { phase = .authenticate(.gmail) }
                }
                ProviderButton(
                    name: "Microsoft 365",
                    icon: "envelope.fill",
                    color: .blue,
                    subtitle: "Outlook, Exchange Online"
                ) {
                    withAnimation { phase = .authenticate(.outlook) }
                }
                ProviderButton(
                    name: "Other IMAP",
                    icon: "server.rack",
                    color: .secondary,
                    subtitle: "Fastmail, iCloud, Yahoo, custom"
                ) {
                    withAnimation { phase = .authenticate(.other) }
                }
            }
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Phase 2: Authenticate

    @ViewBuilder
    private func authenticateView(provider: EmailProvider) -> some View {
        VStack(spacing: 16) {
            switch provider {
            case .gmail, .outlook:
                // OAuth flow
                Text("Sign in with \(provider.displayName) to grant Manifold read-only access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Sign in with \(provider.displayName)") {
                    // Trigger OAuth flow
                    // On success: withAnimation { phase = .importSettings(provider) }
                }
                .buttonStyle(.borderedProminent)

            default:
                // Manual IMAP form
                IMAPFormView(onSuccess: {
                    withAnimation { phase = .importSettings(provider) }
                })
            }
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Phase 3: Import Settings

    @ViewBuilder
    private func importSettingsView(provider: EmailProvider) -> some View {
        VStack(spacing: 16) {
            Text("Choose which mailboxes to back up.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Mailbox selection list
            // "All Mail" toggle at top
            // Individual mailbox checkboxes

            Button("Start Backup") {
                withAnimation { phase = .startingProtection }
                // Begin initial sync
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Phase 4: Starting Protection

    private var startingProtectionView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Starting email backup…")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("This may take a few minutes for large mailboxes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Phase 5: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Account added.")
                .font(.title3.weight(.semibold))

            Text("Manifold will continuously back up new messages.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}
```

### Step 14.5: `ProviderButton` component

```swift
struct ProviderButton: View {
    let name: String
    let icon: String
    let color: Color
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
```

### Step 14.6: Create `Models/MailSetupModel.swift`

```swift
@Observable
@MainActor
final class MailSetupModel {
    var selectedProvider: EmailProvider?
    var oauthToken: String?
    var imapServer: String = ""
    var imapPort: Int = 993
    var username: String = ""
    var password: String = ""
    var useSSL: Bool = true

    var isValidating = false
    var validationError: String?

    func validateIMAPConnection() async -> Bool {
        isValidating = true
        defer { isValidating = false }
        // Attempt IMAP connection with provided credentials
        // Return true on success, set validationError on failure
        return false // placeholder
    }

    func startOAuthFlow(provider: EmailProvider) async {
        // Launch ASWebAuthenticationSession for Google/Microsoft OAuth
        // Store token on success
    }
}
```

### Step 14.7: Empty states

Create the three empty state views that plug into the main UI (from Phase 10 of the main plan):

**`Views/EmptyStates/NoAgentsConnectedView.swift`**:
```swift
struct NoAgentsConnectedView: View {
    @State private var showClaudeSheet = false
    @State private var showCodexSheet = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No AI agents connected.")
                .font(.title3.weight(.medium))

            Text("Connect Claude or Codex to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Set Up Claude") { showClaudeSheet = true }
                    .buttonStyle(.borderedProminent)
                Button("Set Up Codex") { showCodexSheet = true }
                    .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showClaudeSheet) { ConnectClaudeSheet() }
        .sheet(isPresented: $showCodexSheet) { ConnectCodexSheet() }
    }
}
```

**`Views/EmptyStates/NoEmailAccountsView.swift`**:
```swift
struct NoEmailAccountsView: View {
    @State private var showMailSetup = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No email accounts.")
                .font(.title3.weight(.medium))

            Text("Add an account to back up email and control what agents can see.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Email Account") { showMailSetup = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showMailSetup) { AddMailAccountSheet() }
    }
}
```

**`Views/EmptyStates/NoAccessGrantedView.swift`**:
```swift
struct NoAccessGrantedView: View {
    let agent: TargetApp
    @Environment(ManifoldStore.self) var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("\(agent.displayName) is connected but has no access.")
                .font(.title3.weight(.medium))

            Text("Grant access to files or email to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Review & Update Access") {
                store.requestReviewSheet(reason: .firstGrant(agent))
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

### Validation
- Claude sheet shows 3 live checks, "Install Extension" triggers .mcpb install
- Codex sheet shows 3 live checks, "Add to Codex" runs `codex mcp add`
- Both sheets re-check on appear (Rule 6)
- Technical details (paths, commands) are behind disclosure groups (Rule 5)
- Email setup flows: provider pick → authenticate → import → done
- OAuth triggers for Google/Microsoft, IMAP form for Other
- All three empty states render correctly and link to their setup sheets
- No raw JSON or TOML is ever shown on the main surface

---

## File Tree Summary

After phases 11–14, the Views and Models directories look like this:

```
ManifoldApp/ManifoldApp/
├── Views/
│   ├── MainView.swift                     (from Phase 2)
│   ├── Settings/
│   │   ├── SettingsView.swift             ← NEW (Phase 12)
│   │   ├── GeneralSettingsPane.swift      ← NEW (Phase 12)
│   │   ├── AIAppsSettingsPane.swift       ← NEW (Phase 12)
│   │   ├── MailSettingsPane.swift         ← NEW (Phase 12)
│   │   └── StorageSettingsPane.swift      ← NEW (Phase 12)
│   ├── Setup/
│   │   ├── SetupAssistantView.swift       ← NEW (Phase 13)
│   │   ├── ConnectClaudeSheet.swift       ← NEW (Phase 14)
│   │   ├── ConnectCodexSheet.swift        ← NEW (Phase 14)
│   │   └── AddMailAccountSheet.swift      ← NEW (Phase 14)
│   ├── EmptyStates/
│   │   ├── NoAgentsConnectedView.swift    ← NEW (Phase 14)
│   │   ├── NoEmailAccountsView.swift      ← NEW (Phase 14)
│   │   └── NoAccessGrantedView.swift      ← NEW (Phase 14)
│   ├── Components/
│   │   ├── AgentSettingsCard.swift        ← NEW (Phase 12)
│   │   ├── CheckRow.swift                 ← NEW (Phase 12)
│   │   ├── LiveCheckRow.swift             ← NEW (Phase 14)
│   │   ├── ProviderButton.swift           ← NEW (Phase 14)
│   │   ├── DetailLine.swift               ← NEW (Phase 14)
│   │   └── ... (existing components)
│   ├── ... (existing views from Phases 0–10)
│   ├── SetupView.swift                    ← DELETE (Phase 12)
│   └── OnboardingView.swift               ← DELETE (Phase 13)
├── Models/
│   ├── IntegrationHealthModel.swift       ← NEW (Phase 11)
│   ├── AgentConnectionState.swift         ← NEW (Phase 11)
│   ├── MailSetupModel.swift               ← NEW (Phase 14)
│   ├── SetupModel.swift                   ← MODIFY: preferences only (Phase 11)
│   ├── ManifoldStore.swift                ← MODIFY: add integrationHealth (Phase 11)
│   └── ... (existing models)
```

---

## Implementation Order and Dependencies

```
Phase 11: IntegrationHealthModel
    ├── No UI dependencies
    ├── Depends on: ManifoldStore, TargetApp (from Phase 0)
    └── Must complete before: Phases 12, 13, 14

Phase 12: Settings Window
    ├── Depends on: Phase 11 (IntegrationHealthModel)
    ├── Depends on: Phase 14.1–14.3 (connection sheets, for the "Set Up" buttons)
    └── Can partially build without Phase 14 (use placeholder sheets)

Phase 13: Setup Assistant
    ├── Depends on: Phase 11 (IntegrationHealthModel)
    ├── Depends on: Phase 14 (all sheets, for Screen 2 and Screen 3)
    └── Can partially build without Phase 14 (use placeholder sheets)

Phase 14: Connection Sheets + Email + Empty States
    ├── Depends on: Phase 11 (IntegrationHealthModel)
    └── Sheets are standalone — build them first, then wire into Phases 12/13
```

**Recommended build order**: 11 → 14 (sheets) → 12 (Settings) → 13 (Setup Assistant)

This lets you build the atomic pieces first (health model, sheets), then compose them into the Settings and Setup Assistant surfaces.

---

## Testing Strategy

| Phase | What to test |
|-------|-------------|
| 11 | `IntegrationHealthModel.checkAll()` populates states correctly. `AgentConnectionState.overallStatus` rollup logic. Shim compatibility for `mcpInstalled` etc. |
| 12 | Settings opens with 4 tabs. AI Apps pane shows live status. Re-checks on appear. "Set Up" opens correct sheet. |
| 13 | First launch shows assistant. 4 screens navigate correctly. Skip works. Finish sets `hasCompletedOnboarding`. Subsequent launches skip. |
| 14 | Claude sheet: 3 checks update live. Extension install triggers. Codex sheet: `codex mcp add` runs. Email: provider flow completes. Empty states render and link to sheets. |

---

## Reference: Connection Paths

| Agent | Check 1 | Check 2 | Check 3 |
|-------|---------|---------|---------|
| Claude | `/Applications/Claude.app` exists | `claude_desktop_config.json` has `manifold` entry OR `.mcpb` registered | MCP binary exists + config correct |
| Codex | `codex` binary in PATH | `~/.codex/auth.json` exists | `~/.codex/config.toml` has `manifold` entry |

| Agent | Install method | User sees |
|-------|---------------|-----------|
| Claude | Claude Desktop Extension (`.mcpb` one-click) | "Install Extension" button |
| Codex | `codex mcp add manifold -- /path/to/binary` | "Add to Codex" button |

---

## Reference Documents

| Document | Use for |
|----------|---------|
| `design/LAYOUT-SPEC-v4.md` | Source of truth for Overview empty states, Settings feature→location map |
| `design/CLAUDE-CODE-IMPLEMENTATION-PLAN.md` | Phases 0–10, code patterns, animation curves, keyboard shortcuts |
| `design/manifold-wireframe-v4.html` | Visual reference only |
| `swiftui-pro` skill | **INVOKE BEFORE WRITING CODE** — macOS 26 Liquid Glass, Form, Settings patterns |
