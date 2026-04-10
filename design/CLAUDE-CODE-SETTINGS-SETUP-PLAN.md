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
| `Models/MailSetupModel.swift` | View-model wrapper around existing `OAuthManager` + `EmailAccountModel` |
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

> **Research-backed design decisions:**
>
> - **Claude has 3 checks**: app installed, MCP configured (via ConfigWriter JSON *or* .mcpb), live connection (via existing `ManifoldNotification` system). The `.mcpb` install is user-initiated (double-click) — Anthropic provides no programmatic install API. So "configured" means Manifold found its entry in `claude_desktop_config.json`, regardless of how it got there.
> - **Codex has 2 checks, not 3**: CLI installed + Manifold MCP registered in `config.toml`. The original plan had a "Signed in" check, but Codex stores auth in macOS Keychain by default (service name "Codex Auth"), falling back to `~/.codex/auth.json` only if Keychain is unavailable. Querying another app's Keychain item requires entitlements we don't have. Checking `auth.json` would give false negatives on most installs. Drop it — if the user isn't signed in, `codex mcp add` will surface the error directly.
> - **Live connection uses existing infrastructure**: `ManifoldStore` already tracks `isConnected` via `ManifoldNotification.agentConnected`/`.agentDisconnected` plus a 5-second audit-log polling fallback (300-second timeout). The health model should read this, not duplicate it.

```swift
import Foundation

/// Connection health for a single AI agent.
public enum AgentConnectionStatus: String, Sendable {
    case unknown        // Not yet checked
    case checking       // Active health check in progress
    case notInstalled   // App/CLI not found on disk
    case installed      // App/CLI found but not configured for Manifold
    case configured     // Config exists but connection not verified
    case connected      // Live MCP handshake succeeded (via ManifoldNotification)
    case error          // Check failed with an error
}

@Observable
@MainActor
public final class AgentConnectionState: Identifiable {
    public let id: TargetApp

    // Claude-specific checks (3)
    var appInstalled: AgentConnectionStatus = .unknown       // Claude Desktop.app exists
    var mcpConfigured: AgentConnectionStatus = .unknown      // manifold entry in claude_desktop_config.json
    var connectionVerified: AgentConnectionStatus = .unknown  // Live MCP connection (from ManifoldStore.isConnected)

    // Codex-specific checks (2 — no "signed in" check, see note above)
    var cliInstalled: AgentConnectionStatus = .unknown       // `codex` binary in PATH
    var mcpAdded: AgentConnectionStatus = .unknown           // `manifold` in ~/.codex/config.toml

    var errorDetail: String?

    /// Overall rollup for the agent card badge.
    var overallStatus: AgentConnectionStatus {
        switch id {
        case .cowork:
            if connectionVerified == .connected { return .connected }
            if [appInstalled, mcpConfigured, connectionVerified].contains(.error) { return .error }
            if appInstalled == .notInstalled { return .notInstalled }
            if mcpConfigured == .installed { return .configured }
            return .notInstalled
        case .codex:
            if mcpAdded == .connected || mcpAdded == .installed { return .configured }
            if [cliInstalled, mcpAdded].contains(.error) { return .error }
            if cliInstalled == .notInstalled { return .notInstalled }
            return .notInstalled
        }
    }

    /// Number of checks for this agent (used by UI to render the right number of rows).
    var checkCount: Int {
        switch id {
        case .cowork: return 3
        case .codex: return 2
        }
    }

    init(agent: TargetApp) { self.id = agent }
}
```

### Step 11.2: Create `Models/IntegrationHealthModel.swift`

> **Key design decisions backed by codebase research:**
>
> - **Claude "MCP configured" check**: `ConfigWriter` already writes to `claude_desktop_config.json` with a `"manifold"` key under `mcpServers`, passing `--agent cowork` as args. The health check reads the same file the same way. This is the same check the old `SetupModel.checkAgentConfigs()` did, but structured.
> - **Claude "connection verified" check**: `ManifoldStore` already has `isConnected` (set by `ManifoldNotification.agentConnected`/`.agentDisconnected`) and `connectedAgent` (string). The health model reads these — it does NOT duplicate the notification/polling infrastructure.
> - **Codex has 2 checks only**: CLI existence + `config.toml` manifold entry. Auth is in Keychain (inaccessible to us). The `config.toml` format is `[mcp_servers.manifold]` with `command` and `args` keys — this is what `ConfigWriter.writeCodexConfig()` writes.
> - **No `.mcpb` detection**: The plan originally checked for `.mcpb` registration. But `.mcpb` is just a delivery mechanism — once installed, the result is the same `claude_desktop_config.json` entry. Checking the config file covers both install paths.

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "health")

@Observable
@MainActor
final class IntegrationHealthModel {
    var claude = AgentConnectionState(agent: .cowork)
    var codex = AgentConnectionState(agent: .codex)

    /// Reference to ManifoldStore for runtime connection state.
    /// Set during ManifoldStore.init() — avoids circular init.
    weak var store: ManifoldStore?

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

        // 2. Manifold MCP configured in claude_desktop_config.json?
        //    This covers BOTH install paths:
        //    - ConfigWriter.installAll() writes the JSON entry directly
        //    - .mcpb double-click also results in a config entry
        //    Either way, the "manifold" key in mcpServers is the proof.
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

        // 3. Live connection verified?
        //    ManifoldStore already tracks this via ManifoldNotification.agentConnected/
        //    .agentDisconnected + 5-second audit-log polling (300s timeout).
        //    We read the existing state rather than duplicating the mechanism.
        if let store, store.isConnected, store.connectedAgent == "Claude" || store.connectedAgent == "cowork" {
            claude.connectionVerified = .connected
        } else if claude.mcpConfigured == .installed {
            claude.connectionVerified = .configured  // Configured but not live right now
        } else {
            claude.connectionVerified = .notInstalled
        }
    }

    // MARK: - Codex checks

    func checkCodex() async {
        codex.cliInstalled = .checking
        codex.mcpAdded = .checking

        // 1. Codex CLI installed?
        //    Check common install locations. Codex installs via npm/brew.
        let codexPaths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        let homeCodex = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/codex").path
        let found = (codexPaths + [homeCodex]).contains { FileManager.default.fileExists(atPath: $0) }
        codex.cliInstalled = found ? .installed : .notInstalled

        guard found else {
            codex.mcpAdded = .notInstalled
            return
        }

        // 2. Manifold MCP added to config.toml?
        //    ConfigWriter writes: [mcp_servers.manifold] with command + args.
        //    `codex mcp add manifold -- /path/to/binary` writes the same format.
        let tomlPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
        if let contents = try? String(contentsOfFile: tomlPath, encoding: .utf8),
           contents.contains("[mcp_servers.manifold]") || contents.contains("mcp_servers.manifold") {
            codex.mcpAdded = .installed
        } else {
            codex.mcpAdded = .notInstalled
        }

        // NOTE: No "signed in" check. Codex stores auth in macOS Keychain
        // (service "Codex Auth") by default. Querying another app's Keychain
        // entry requires entitlements we don't have. Checking the fallback
        // ~/.codex/auth.json would give false negatives on most installs.
        // If the user isn't signed in, `codex mcp add` will surface the error.
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
// REMOVE these delegated properties from ManifoldStore:
//   mcpInstalled, claudeDesktopConfigured, codexConfigured,
//   checkMCPInstalled(), checkAgentConfigs()
// They currently delegate to setup.xxx — replace with integrationHealth.

// ADD:
let integrationHealth = IntegrationHealthModel()

// In ManifoldStore.init(), wire the back-reference:
// integrationHealth.store = self

// Computed compatibility shims (for existing code that reads the old booleans):
var mcpInstalled: Bool {
    integrationHealth.claude.mcpConfigured == .installed
}
var claudeDesktopConfigured: Bool {
    integrationHealth.claude.mcpConfigured == .installed
}
var codexConfigured: Bool {
    integrationHealth.codex.mcpAdded == .installed
}
```

> **Why `weak var store`?** IntegrationHealthModel needs to read `ManifoldStore.isConnected` and `connectedAgent` for the Claude "connection verified" check. These are already maintained by the existing notification + polling system. The alternative — passing `isConnected` as a parameter to `checkClaude()` — is cleaner but means the caller must know to pass it, which breaks the simple `checkAll()` API. The weak reference is a pragmatic tradeoff.

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

            // Check rows (3 for Claude, 2 for Codex — see Phase 11 notes)
            switch agent {
            case .cowork:
                CheckRow("App installed", status: state.appInstalled)
                CheckRow("MCP configured", status: state.mcpConfigured)
                CheckRow("Connection verified", status: state.connectionVerified)
            case .codex:
                CheckRow("CLI installed", status: state.cliInstalled)
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

> **Research finding — .mcpb cannot be installed programmatically.**
> Anthropic's Desktop Extension system is explicitly designed to require user interaction (double-click or drag into Claude Desktop). There is no silent install API, URL scheme, or programmatic registration mechanism. The `.mcpb` file is a ZIP archive containing MCP server code + manifest.json, and Claude Desktop shows an interactive installation UI when the user opens it.
>
> **Two install paths, one check:**
> 1. **Preferred (production):** Manifold ships a pre-built `.mcpb` in its app bundle. "Install" reveals it in Finder. User double-clicks it. Claude Desktop registers the extension. Result: a `"manifold"` entry appears in `claude_desktop_config.json`.
> 2. **Fallback (development / .mcpb unavailable):** `ConfigWriter.installAll()` writes the JSON entry directly, same as the current `SetupModel.installMCP()`. This still works — Anthropic deprecated it as the *primary* user-facing path but it's still functional.
>
> Both paths produce the same result: a `"manifold"` key in `mcpServers`. The health check reads that key and doesn't care how it got there.

Three live checks:
1. **Claude Desktop installed** — `/Applications/Claude.app` exists
2. **MCP configured** — `"manifold"` entry in `claude_desktop_config.json` (covers both .mcpb and ConfigWriter paths)
3. **Connection verified** — live MCP connection (via existing `ManifoldStore.isConnected` notification system)

```swift
struct ConnectClaudeSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false

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
                        if let url = URL(string: "https://claude.ai/download") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    actionLabel: "Download"
                )

                // Check 2: MCP configured
                LiveCheckRow(
                    label: "MCP configured",
                    status: store.integrationHealth.claude.mcpConfigured,
                    action: {
                        installing = true
                        store.installManifoldForClaude()
                        Task {
                            await store.integrationHealth.checkClaude()
                            installing = false
                        }
                    },
                    actionLabel: installing ? "Installing…" : "Install"
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
                        if store.integrationHealth.claude.mcpConfigured == .notInstalled {
                            Text("Manifold will write its MCP server entry to the Claude config file. If you prefer, you can install the .mcpb extension manually instead.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
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

                if store.integrationHealth.claude.mcpConfigured == .installed {
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

**Claude install automation — two paths:**

```swift
// In ManifoldStore (or extract to a dedicated MCPInstaller):
func installManifoldForClaude() {
    // Try .mcpb first (preferred), fall back to ConfigWriter (always works).
    //
    // Path 1: .mcpb — reveal in Finder for user to double-click.
    // Anthropic requires user interaction for extension registration.
    if let mcpbURL = Bundle.main.url(forResource: "manifold", withExtension: "mcpb") {
        // Reveal in Finder — user double-clicks to install
        NSWorkspace.shared.activateFileViewerSelecting([mcpbURL])
        return
    }

    // Path 2: ConfigWriter — writes claude_desktop_config.json directly.
    // This is the existing installMCP() logic, battle-tested.
    // Works silently, no user interaction needed, but Anthropic considers
    // this the "legacy" path. Still fully functional as of April 2026.
    do {
        let destPath = Self.mcpBinaryPath
        let destURL = URL(fileURLWithPath: destPath)
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Copy binary from bundle or debug build...
        // (same logic as current SetupModel.installMCP())
        try ConfigWriter(binaryPath: destPath).installAll()
    } catch {
        integrationHealth.claude.errorDetail = error.localizedDescription
    }
}
```

> **Why not .mcpb-only?** Because it requires the user to leave Manifold, find a file in Finder, and double-click it. That's a broken flow in a Setup Assistant. ConfigWriter gives us a one-click "Install" that works silently. Ship both: ConfigWriter as the automation path, `.mcpb` mentioned in the disclosure group for users who prefer the official extension route. When Anthropic adds a programmatic install API (if ever), switch to that.

### Step 14.2: Create `Views/Setup/ConnectCodexSheet.swift`

> **Research finding — Codex auth is inaccessible, so 2 checks not 3.**
> Codex stores authentication in macOS Keychain (service "Codex Auth") by default, with `~/.codex/auth.json` as a fallback only when Keychain is unavailable. We can't query another app's Keychain entry without entitlements. Checking `auth.json` would show "Not found" for the majority of users who have Keychain working fine. A "Signed in" check that gives false negatives is worse than no check — it creates unnecessary panic.
>
> If the user isn't signed in, `codex mcp add` will fail with a clear auth error. Let Codex handle its own auth UX.
>
> **Verified command format**: `codex mcp add <name> -- <command>` with optional `--env VAR=VALUE`. Config result is `[mcp_servers.manifold]` in `~/.codex/config.toml` with `command` and `args` keys.

Two live checks:
1. **Codex installed** — `codex` binary found in PATH
2. **Manifold added** — `[mcp_servers.manifold]` section in `~/.codex/config.toml`

```swift
struct ConnectCodexSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var addError: String?

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
                        if let url = URL(string: "https://openai.com/index/introducing-codex/") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    actionLabel: "Install"
                )

                // Check 2: Manifold MCP added
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
                    actionLabel: adding ? "Adding…" : "Add to Codex"
                )

                // Show error from codex mcp add (e.g. auth failure)
                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 36)  // Align with check row text
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

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Check Again") {
                    Task { await store.integrationHealth.checkCodex() }
                }
                .buttonStyle(.bordered)

                if store.integrationHealth.codex.mcpAdded == .installed {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 380)  // Shorter than Claude sheet — 2 checks not 3
        .task { await store.integrationHealth.checkCodex() }
    }
}
```

**Codex MCP add automation:**

```swift
// In ManifoldStore:
func addManifoldToCodex(completion: @escaping (String?) -> Void) {
    // Runs: codex mcp add manifold -- /path/to/manifold-mcp --agent codex
    // On success: writes [mcp_servers.manifold] to ~/.codex/config.toml
    // On failure: returns stderr (e.g. "Not signed in — run `codex login`")
    Task.detached {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "mcp", "add", "manifold", "--", Self.mcpBinaryPath]
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if process.terminationStatus == 0 {
                    completion(nil)
                    Task { await self.integrationHealth.checkCodex() }
                } else {
                    completion(errorString ?? "codex mcp add failed (exit \(process.terminationStatus))")
                }
            }
        } catch {
            await MainActor.run {
                completion(error.localizedDescription)
            }
        }
    }
}
```

> **Why surface stderr?** If Codex isn't signed in, the error message will say so explicitly. Showing it directly (in `.red` caption text below the check row) is more honest than a generic "Error" badge, and lets the user know exactly what to do ("run `codex login`") without us having to guess at their auth state.

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

### Step 14.6: `MailSetupModel` — Wrap Existing OAuth Infrastructure

> **Codebase finding: full OAuth2 stack already exists.**
> - `OAuthManager.swift` in ManifoldKit has PKCE-compliant flows for Gmail + Microsoft 365
> - `OAuthConfig` structs define `clientID`, `authURL`, `tokenURL`, `scopes`, `redirectScheme`
> - Redirect scheme: `com.spatialduality.manifold://oauth/callback`
> - Token storage: `KeychainHelper` with service key `oauth.<accountID>`
> - XOAUTH2 SASL support for IMAP auth via `xoauth2String(user:accessToken:)`
> - `EmailAccountSetupView` already has provider detection via `MailProviderDetector.detectWithDiscovery()`
> - The existing view has a multi-step connection test (DNS → TLS → Auth → Discover mailboxes)
>
> **What this means:** `MailSetupModel` is NOT a from-scratch OAuth implementation. It's a thin view-model wrapper around the existing `OAuthManager` + `EmailAccountModel` that adapts the provider-first flow for the new `AddMailAccountSheet`.
>
> **What's missing:** The OAuth client IDs. `OAuthManager` has the plumbing but `OAuthConfig` requires a registered `clientID` for Google Cloud and Azure AD. The current `EmailAccountSetupView` falls back to app-password flow when OAuth fails. The new sheet should do the same — OAuth as the happy path, app-password as fallback.

```swift
@Observable
@MainActor
final class MailSetupModel {
    var selectedProvider: EmailProvider?
    var phase: MailSetupPhase = .chooseProvider

    // OAuth (delegates to existing OAuthManager)
    var oauthInProgress = false
    var oauthError: String?

    // IMAP fallback
    var imapServer: String = ""
    var imapPort: Int = 993
    var username: String = ""
    var password: String = ""
    var useSSL: Bool = true

    // Connection test
    var isValidating = false
    var validationError: String?
    var connectionSteps: [ConnectionTestStep] = []

    enum MailSetupPhase {
        case chooseProvider
        case authenticate(EmailProvider)
        case importSettings(EmailProvider)
        case startingProtection
        case done
    }

    /// Trigger OAuth via existing OAuthManager.
    /// On success, stores token in Keychain and advances phase.
    func startOAuth(provider: EmailProvider) async {
        oauthInProgress = true
        oauthError = nil
        do {
            // OAuthManager.shared.authenticate(config:) already handles:
            //   - PKCE code_verifier/challenge generation
            //   - ASWebAuthenticationSession launch
            //   - Token exchange
            //   - KeychainHelper storage
            let config = OAuthManager.config(for: provider)
            let tokenPair = try await OAuthManager.shared.authenticate(config: config)
            // Token stored in Keychain by OAuthManager
            phase = .importSettings(provider)
        } catch {
            oauthError = "OAuth failed: \(error.localizedDescription). You can use an app password instead."
        }
        oauthInProgress = false
    }

    /// Validate IMAP connection (for .other providers or OAuth fallback).
    /// Delegates to existing EmailAccountModel.testConnection().
    func validateIMAPConnection() async -> Bool {
        isValidating = true
        defer { isValidating = false }
        // Use existing multi-step connection test from EmailAccountSetupView:
        //   DNS resolve → TLS → Auth → Discover mailboxes
        // Return true on success, set validationError on failure
        return false // placeholder — wire to existing test infrastructure
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
- Claude sheet shows 3 live checks; "Install" runs ConfigWriter (or reveals .mcpb if bundled)
- Codex sheet shows 2 live checks (no "Signed in"); "Add to Codex" runs `codex mcp add` and surfaces stderr on failure
- Both sheets re-check on appear (Rule 6)
- Technical details (paths, commands) are behind disclosure groups (Rule 5)
- Email setup flows: provider pick → OAuth (or app-password fallback) → import → done
- OAuth uses existing `OAuthManager` + `KeychainHelper` infrastructure
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
| 14 | Claude sheet: 3 checks update live, ConfigWriter installs silently. Codex sheet: 2 checks, `codex mcp add` runs and surfaces errors. Email: OAuth via existing OAuthManager, app-password fallback. Empty states link to sheets. |

---

## Reference: Connection Paths (Research-Verified)

| Agent | Check 1 | Check 2 | Check 3 |
|-------|---------|---------|---------|
| Claude | `/Applications/Claude.app` exists | `claude_desktop_config.json` has `"manifold"` in `mcpServers` | `ManifoldStore.isConnected` + `connectedAgent == "Claude"` |
| Codex | `codex` binary in PATH (`/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`) | `~/.codex/config.toml` contains `[mcp_servers.manifold]` | *(no third check — auth is in Keychain, inaccessible)* |

| Agent | Primary install | Fallback | User sees |
|-------|----------------|----------|-----------|
| Claude | `ConfigWriter.installAll()` — writes JSON silently | Reveal `.mcpb` in Finder for manual install | "Install" button |
| Codex | `codex mcp add manifold -- /path/to/binary` (Process) | `ConfigWriter.writeCodexConfig()` | "Add to Codex" button |

### Why these choices

**Claude: ConfigWriter over .mcpb as primary.** Anthropic designed .mcpb for end-user distribution (double-click to install). There is no programmatic install API — NSWorkspace.shared.open() of a .mcpb would require user interaction outside Manifold. ConfigWriter gives us silent, one-click setup. The .mcpb path exists as a manual alternative behind the disclosure group.

**Codex: 2 checks not 3.** Codex defaults to macOS Keychain for auth (service "Codex Auth"), with `~/.codex/auth.json` as fallback only when Keychain is unavailable (`cli_auth_credentials_store = "file"` in config). Checking another app's Keychain requires entitlements. Checking `auth.json` gives false negatives on default installs. If auth is missing, `codex mcp add` exits non-zero with a descriptive error — we surface that stderr directly.

**Email: existing OAuth + app-password fallback.** `OAuthManager.swift` already has PKCE flows for Gmail/Microsoft, `KeychainHelper` for token storage, and `xoauth2String()` for IMAP SASL. The gap is registered OAuth client IDs (Google Cloud, Azure AD). Until those are provisioned, app-password is the working path. The UI should try OAuth first, catch the error, and offer app-password as fallback — not hide OAuth behind a feature flag.

---

## Reference Documents

| Document | Use for |
|----------|---------|
| `design/LAYOUT-SPEC-v4.md` | Source of truth for Overview empty states, Settings feature→location map |
| `design/CLAUDE-CODE-IMPLEMENTATION-PLAN.md` | Phases 0–10, code patterns, animation curves, keyboard shortcuts |
| `design/manifold-wireframe-v4.html` | Visual reference only |
| `swiftui-pro` skill | **INVOKE BEFORE WRITING CODE** — macOS 26 Liquid Glass, Form, Settings patterns |
