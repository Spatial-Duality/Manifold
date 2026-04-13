# Manifold Menu Bar Extra — Implementation Spec

> **Purpose**: Turn Manifold's menu bar extra from a legacy session-model stub into the fastest way to answer "what can AI see right now?" and the fastest way to change that answer.
>
> **Model alignment**: This spec follows the April 13, 2026 product spec throughout. No "session" language. The menu bar reflects the same per-agent access, tracked workspace, and coverage model as the main app.
>
> **Companion to**: PRODUCT-SPEC.md, APPLE-DESIGN-EXCELLENCE-GUIDE.md, and DESIGN-STANDARDS.md.
>
> **Three phases**: Phase 1 (status + control), Phase 2 (approval queue + activity), Phase 3 (system extensions + App Intents).

---

## What the Menu Bar Must Answer

Five questions, instantly:

1. **Is any AI active right now?** → Icon state + header
2. **What can each agent currently see?** → Per-agent cards
3. **Is a Tracked Work Block running?** → Work block strip
4. **Is an agent asking for more access?** → Approval badge (Phase 2)
5. **How do I stop or change it immediately?** → Pause All + per-agent pause

---

## Current State

`ManifoldApp.swift` already has a `MenuBarExtra` (lines 87–89) using the pull-down menu style. It contains three zones: session section (old model), connection section, and sources section. It references `store.hasActiveSession`, `store.startSession()`, `store.endSession()` — all from the legacy `SessionModel`.

**Current direction**: The window-style panel already exists on `main`. This document now serves as the behavioral spec for keeping that panel aligned with the current policy, coverage, and tracked workspace model rather than the retired session model.

---

## Phase 1: Status + Control

### 1.0 Menu Bar Icon

**One monochrome SF Symbol, not a wordmark.** Menu bars get crowded, and on notched MacBooks icons can be pushed off-screen.

```swift
// In ManifoldApp.swift
MenuBarExtra {
    MenuBarPanelView()
        .environment(store)
} label: {
    Label("Manifold", systemImage: menuBarIconName)
}
.menuBarExtraStyle(.window)
```

**Icon states** (computed property on `ManifoldStore`):

| State | Icon | Adornment |
|-------|------|-----------|
| No agents connected, no policy | `shield.slash` | None |
| Connected, standing access active, no work block | `shield.checkered` | None |
| Connected, work block active | `shield.checkered` | Small filled circle (badge via overlay) |
| Any agent paused | `shield.checkered` | Orange tint or exclamation variant |
| Pending approval (Phase 2) | `shield.checkered` | Red badge dot |

```swift
var menuBarIconName: String {
    if !isConnected && policy.claudePolicy == nil && policy.codexPolicy == nil {
        return "shield.slash"
    }
    if policy.claudePolicy?.isPaused == true || policy.codexPolicy?.isPaused == true {
        return "shield.checkered.fill" // or a tinted variant
    }
    return "shield.checkered"
}
```

The icon should use SF Symbol template rendering so it adapts to the menu bar's light/dark state automatically.

**Accessibility**: The `Label` text "Manifold" remains for VoiceOver. Add a dynamic accessibility value:

```swift
.accessibilityValue(menuBarAccessibilityStatus)

var menuBarAccessibilityStatus: String {
    var parts: [String] = []
    if let claude = policy.claudePolicy, !claude.isPaused {
        parts.append("Claude active, \(claude.allowedSourceIDs.count) sources")
    }
    if let codex = policy.codexPolicy, !codex.isPaused {
        parts.append("Codex active, \(codex.allowedSourceIDs.count) sources")
    }
    if let block = policy.activeWorkBlock {
        parts.append("Tracked work block running")
    }
    return parts.isEmpty ? "No active access" : parts.joined(separator: ". ")
}
```

### 1.1 Panel Structure

Window-style `MenuBarExtra` with a fixed width of ~380pt. The panel uses the system menu bar extra window chrome (Liquid Glass on macOS 26). Content inside is opaque and structured.

**Section order is fixed across all states** — this builds spatial memory:

```
┌─────────────────────────────────────────┐
│ HEADER: Global trust state + Pause All  │  ← always visible
├─────────────────────────────────────────┤
│ WORK BLOCK STRIP (if active)            │  ← only when work block running
├─────────────────────────────────────────┤
│ AGENT CARD: Claude                      │  ← always if policy exists
│ AGENT CARD: Codex                       │  ← always if policy exists
├─────────────────────────────────────────┤
│ APPROVAL QUEUE (Phase 2, if non-empty)  │  ← Phase 2 only
├─────────────────────────────────────────┤
│ RECENT ACTIVITY (Phase 2)               │  ← Phase 2 only
├─────────────────────────────────────────┤
│ QUICK ACTIONS                           │  ← always visible
└─────────────────────────────────────────┘
```

### 1.2 Header

```swift
struct MenuBarHeaderView: View {
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manifold")
                    .font(.headline)
                Text(globalStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Pause All — THE panic control
            if anyAgentActive {
                Button("Pause All") {
                    Task {
                        await store.policy.pauseAllAgents()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var anyAgentActive: Bool {
        let claude = store.policy.claudePolicy
        let codex = store.policy.codexPolicy
        return (claude != nil && claude?.isPaused != true) ||
               (codex != nil && codex?.isPaused != true)
    }
    
    private var globalStatusText: String {
        if !store.isConnected {
            return "No agents connected"
        }
        var parts: [String] = []
        if let claude = store.policy.claudePolicy, !claude.isPaused {
            parts.append("Claude active")
        }
        if let codex = store.policy.codexPolicy, !codex.isPaused {
            parts.append("Codex active")
        }
        if parts.isEmpty {
            return "All access paused"
        }
        return parts.joined(separator: " · ")
    }
}
```

**Why "Pause All" is red and `.borderedProminent`**: This is the emergency control. It must be unmistakable. Little Snitch's menu bar works because it gives immediate control over a sensitive system boundary. "Pause All" is Manifold's equivalent — one click to suspend every agent's access. The button disappears when all agents are already paused (no dead control).

### 1.3 Work Block Strip

Only visible when `policy.activeWorkBlock != nil`.

```swift
struct MenuBarWorkBlockStrip: View {
    let block: WorkBlockRecord
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(block.agent == .codex ? Color.purple : Color.blue)
                .frame(width: 8, height: 8)
            
            Text("Tracked Work Block")
                .font(.caption.weight(.medium))
            
            Text("·")
                .foregroundStyle(.tertiary)
            
            // Live elapsed time
            Text(block.startedAt, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Finish") {
                // Opens Review Changes in main app
                NSApp.activate(ignoringOtherApps: true)
                store.triggerFinishWorkBlock()
            }
            .controlSize(.mini)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.06))
    }
}
```

**"Finish" opens the main app**: The Review Changes flow is too complex for inline menu bar treatment. The menu bar shows status and provides the entry point; the main app handles the review. This is the Tailscale lesson — anything requiring more than 2 seconds of attention belongs in the main window.

### 1.4 Agent Cards

One card per agent with an existing policy. Compact, glanceable, actionable.

```swift
struct MenuBarAgentCard: View {
    let agent: TargetApp
    let policy: AgentAccessPolicy
    let isConnected: Bool
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Agent name + connection + pause
            HStack {
                Circle()
                    .fill(agent == .codex ? Color.purple : Color.blue)
                    .frame(width: 8, height: 8)
                Text(agent.displayName)
                    .font(.callout.weight(.medium))
                
                if policy.isPaused {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.12), in: Capsule())
                } else if !isConnected {
                    Text("Offline")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(policy.isPaused ? "Resume" : "Pause") {
                    Task {
                        if policy.isPaused {
                            await store.policy.resumeAgent(agent)
                        } else {
                            await store.policy.pauseAgent(agent)
                        }
                    }
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
                .tint(policy.isPaused ? .green : .orange)
            }
            
            // Row 2: Access summary — one line
            if !policy.isPaused {
                HStack(spacing: 12) {
                    Label("\(policy.allowedSourceIDs.count) sources", systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(policy.allowedEmailDomains.count) domains", systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(policy.emailSensitivity.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(policy.isPaused ? 0.6 : 1.0)
    }
}
```

**What's NOT in the agent card**:
- No per-source list (that's the main app's Files tab)
- No per-domain list (that's the main app's Emails tab)
- No activity feed (Phase 2, and even then just 3–5 items)
- No checkboxes (broadening goes through the Review sheet in the main app)

The card answers "what can this agent see?" at the summary level. If the user needs detail, they click "Open Manifold."

### 1.5 Quick Actions

```swift
struct MenuBarQuickActions: View {
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Start Tracked Work Block (only if none active)
            if store.policy.activeWorkBlock == nil && store.isConnected {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    store.reviewSheetTrigger = ReviewAccessChange(
                        description: "Start tracking changes",
                        kind: .startWorkBlock
                    )
                } label: {
                    Label("Start Tracked Work Block", systemImage: "timeline.selection")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            
            Button {
                NSApp.activate(ignoringOtherApps: true)
                store.selectedTab = .overview
            } label: {
                Label("Open Manifold", systemImage: "macwindow")
            }
            .keyboardShortcut("o")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            Button {
                store.showActivityDrawer = true
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("View Activity", systemImage: "clock.arrow.circlepath")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            Divider()
            
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            Button("Quit Manifold") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
```

### 1.6 Empty States

| State | Panel Content |
|-------|--------------|
| No agents configured | Header + "No AI agents configured. Open Settings to set up Claude or Codex." + Open Settings button |
| Agents configured, none connected | Header + agent cards showing "Offline" + "Agents will appear when Claude or Codex connects via MCP." |
| Connected, no access policy | Header + agent cards with "0 sources, 0 domains" + "Open Manifold to configure access." |

### 1.7 Composing the Panel

```swift
struct MenuBarPanelView: View {
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeaderView()
            
            Divider()
            
            // Work block strip (conditional)
            if let block = store.policy.activeWorkBlock {
                MenuBarWorkBlockStrip(block: block)
                Divider()
            }
            
            // Agent cards
            if let claude = store.policy.claudePolicy {
                MenuBarAgentCard(
                    agent: .cowork,
                    policy: claude,
                    isConnected: store.connectedAgent?.lowercased().contains("claude") == true
                )
            }
            if let codex = store.policy.codexPolicy {
                MenuBarAgentCard(
                    agent: .codex,
                    policy: codex,
                    isConnected: store.connectedAgent?.lowercased().contains("codex") == true
                )
                Divider()
            }
            
            // Phase 2 sections go here
            
            MenuBarQuickActions()
        }
        .frame(width: 380)
    }
}
```

### 1.8 PolicyModel Changes

Add a `pauseAllAgents()` method:

```swift
// In PolicyModel.swift
func pauseAllAgents() async {
    if let claude = claudePolicy, !claude.isPaused {
        await pauseAgent(.cowork)
    }
    if let codex = codexPolicy, !codex.isPaused {
        await pauseAgent(.codex)
    }
}
```

Add a `triggerFinishWorkBlock()` method to `ManifoldStore`:

```swift
func triggerFinishWorkBlock() {
    // Activate main window, navigate to Overview, trigger the finish flow
    selectedTab = .overview
    // The finish flow opens the Review Changes sheet
    Task {
        await session.requestFinishWorkBlock()
    }
}
```

### 1.9 Implementation Notes

**SwiftUI scene structure**: The `MenuBarExtra` with `.menuBarExtraStyle(.window)` gives us a proper NSPanel with system chrome. On macOS 26 this automatically gets Liquid Glass treatment on the panel frame. Content inside is standard SwiftUI.

**Sizing**: The `.frame(width: 380)` sets the panel width. Height is determined by content. SwiftUI handles this automatically for window-style menu bar extras.

**State sharing**: The `MenuBarPanelView` reads from the same `ManifoldStore` instance that the main window uses. No IPC needed — both scenes live in the same process and share the `@State private var store`.

**Notched MacBook handling**: By using a single SF Symbol (not a wordmark), the icon fits in the standard menu bar item width. No special handling needed — macOS manages overflow automatically.

---

## Phase 2: Approval Queue + Recent Activity

### The Approval Queue Decision

**Should Manifold add an approval queue?**

The current model is user-initiated: the user configures policy proactively, and the MCP bridge enforces it fail-closed. An agent that tries to access a file outside its policy gets denied silently. The user never finds out unless they check the audit trail.

This creates a real usability gap. The agent fails, retries, fails again, and eventually works around the limitation or tells the user "I can't access that file." The user then has to: open Manifold, navigate to Files, find the source, check the box (which opens the Review sheet), confirm, go back to the agent. That's 6+ steps for what should be a 1-step decision.

**An approval queue changes this to**: agent hits policy boundary → bridge logs the request → menu bar shows a badge → user taps "Allow" → policy updates → agent retries. Two steps: see the request, approve or deny.

**The risks**:
- **Nagging**: If agents frequently hit boundaries, the queue becomes notification spam. Mitigation: batch related requests (e.g., "Claude wants access to 3 files in ~/Projects/web-app" → one approval for the source folder, not three per-file requests), rate-limit to one notification per source/domain per 5 minutes, and auto-collapse repeated denials.
- **Shifting the trust model**: The product goes from "user sets policy proactively" to "agent requests, user reacts." This is only safe if the default is still deny, requests are rare (only when the agent explicitly hits a boundary), and the user can configure auto-deny for specific agents or categories.
- **Complexity**: Adds a request queue to `ManifoldBridge`, a notification pipeline from the MCP bridge to the UI, and inline approval UI.

**My recommendation: include it, with constraints.**

The approval queue is the feature that makes the menu bar indispensable rather than merely convenient. Without it, the menu bar is a status display. With it, the menu bar becomes the fast path for the most common trust decision. The constraint is: requests must be infrequent, batchable, and always deniable.

**The key design rule**: An approval is a *pre-filled Review & Update Access* flow. The user is still making a deliberate broadening decision — it's just initiated by the agent hitting a wall, not by the user navigating to a table.

### 2.0 Request Model

```swift
// In ManifoldKit/AccessRequest.swift (new file)

/// A request from an agent to access a resource outside its current policy.
public struct AccessRequest: Identifiable, Sendable, Codable {
    public let id: String  // UUID
    public let agent: TargetApp
    public let kind: AccessRequestKind
    public let reason: String?  // Optional agent-provided context
    public let requestedAt: Date
    public var status: AccessRequestStatus
    
    public enum AccessRequestKind: Sendable, Codable {
        case source(path: String, displayName: String)
        case emailDomain(domain: String)
        case sensitivityLoosen(from: EmailSensitivityLevel, to: EmailSensitivityLevel)
    }
    
    public enum AccessRequestStatus: String, Sendable, Codable {
        case pending
        case approved
        case denied
        case expired  // auto-expires after 30 minutes
    }
}
```

### 2.1 MCP Bridge Changes

In `ManifoldBridge.swift`, when the bridge denies access:

```swift
// Current behavior: deny and return error
// New behavior: deny, log request, notify UI

private func handleAccessDenied(
    resource: String,
    agent: TargetApp,
    reason: String
) async {
    // Rate-limit: don't create duplicate requests for the same resource within 5 min
    let recentRequests = await requestStore.pendingRequests(for: agent)
    let isDuplicate = recentRequests.contains { request in
        request.matchesResource(resource) &&
        request.requestedAt.timeIntervalSinceNow > -300
    }
    
    guard !isDuplicate else { return }
    
    let request = AccessRequest(
        id: UUID().uuidString,
        agent: agent,
        kind: .source(path: resource, displayName: URL(fileURLWithPath: resource).lastPathComponent),
        reason: nil,
        requestedAt: Date(),
        status: .pending
    )
    
    await requestStore.addRequest(request)
    
    // Post notification to UI
    await MainActor.run {
        NotificationCenter.default.post(
            name: .manifoldAccessRequested,
            object: nil,
            userInfo: ["requestID": request.id]
        )
    }
    
    // System notification (if app is not frontmost)
    await sendUserNotification(for: request)
}
```

**Batching**: When multiple files in the same source folder are denied, batch them into one request for the parent source. The bridge already knows the source hierarchy.

### 2.2 Request Store

```swift
// In ManifoldKit/RequestStore.swift (new file)

public actor RequestStore {
    private let db: DatabaseConnection
    
    public func pendingRequests(for agent: TargetApp? = nil) -> [AccessRequest] { ... }
    public func addRequest(_ request: AccessRequest) async { ... }
    public func approveRequest(_ id: String) async { ... }
    public func denyRequest(_ id: String) async { ... }
    public func expireStaleRequests() async { ... }  // called on timer, 30-min TTL
    
    /// Batch: collapse multiple file requests into one source request
    public func batchedPendingRequests() -> [BatchedAccessRequest] {
        let pending = pendingRequests()
        // Group file requests by parent source
        // Return one BatchedAccessRequest per source/domain
    }
}
```

### 2.3 Approval Queue UI

```swift
struct MenuBarApprovalQueue: View {
    let requests: [BatchedAccessRequest]
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pending Requests")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                ForEach(requests) { request in
                    MenuBarApprovalRow(request: request)
                }
            }
            Divider()
        }
    }
}

struct MenuBarApprovalRow: View {
    let request: BatchedAccessRequest
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        HStack(spacing: 8) {
            // Agent dot
            Circle()
                .fill(request.agent == .codex ? Color.purple : Color.blue)
                .frame(width: 6, height: 6)
            
            // Request description
            VStack(alignment: .leading, spacing: 1) {
                Text(request.summary)
                    .font(.caption)
                    .lineLimit(1)
                Text(request.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 4) {
                Button {
                    Task { await store.denyAccessRequest(request.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button {
                    // Opens Review & Update Access sheet in main app
                    // pre-populated with this request
                    NSApp.activate(ignoringOtherApps: true)
                    store.reviewSheetTrigger = ReviewAccessChange(
                        description: request.summary,
                        kind: .approveRequest(request.id),
                        preselectedSources: request.sourceIDs,
                        preselectedDomains: request.domains
                    )
                } label: {
                    Text("Review")
                        .font(.caption2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
```

**Critical design decision**: The "Allow" action in the menu bar does NOT directly modify the policy. It opens the Review & Update Access sheet in the main app, pre-populated with the requested resource. This preserves the product rule that **all broadening goes through the Review sheet.** The menu bar is a notification surface and entry point, not a policy editor.

The only inline action is "Deny" (the × button), which is narrowing and therefore safe to do immediately.

### 2.4 Recent Activity

Last 3–5 trust-relevant events. Not the full audit trail — just enough to know if something needs attention.

```swift
struct MenuBarRecentActivity: View {
    @Environment(ManifoldStore.self) var store
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            ForEach(store.recentTrustEvents.prefix(5)) { event in
                HStack(spacing: 8) {
                    Image(systemName: event.icon)
                        .font(.caption)
                        .foregroundStyle(event.color)
                        .frame(width: 14)
                    Text(event.summary)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(ManifoldDateFormatter.relative(event.date))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
    }
}
```

**Trust events** (from `AuditStore`): access granted, access revoked, source added, source removed, domain checked/unchecked, sensitivity changed, work block started/finished, access paused/resumed, request denied.

### 2.5 System Notifications

When the app is not frontmost and a new access request arrives:

```swift
func sendUserNotification(for request: AccessRequest) async {
    let content = UNMutableNotificationContent()
    content.title = "\(request.agent.displayName) needs access"
    content.body = request.summaryText
    content.categoryIdentifier = "ACCESS_REQUEST"
    content.sound = nil  // silent — the menu bar badge is enough
    
    // Action buttons in the notification
    let reviewAction = UNNotificationAction(
        identifier: "REVIEW",
        title: "Review in Manifold",
        options: [.foreground]
    )
    let denyAction = UNNotificationAction(
        identifier: "DENY",
        title: "Deny",
        options: [.destructive]
    )
    
    let category = UNNotificationCategory(
        identifier: "ACCESS_REQUEST",
        actions: [reviewAction, denyAction],
        intentIdentifiers: []
    )
    
    UNUserNotificationCenter.current().setNotificationCategories([category])
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let notifRequest = UNNotificationRequest(
        identifier: request.id,
        content: content,
        trigger: trigger
    )
    try? await UNUserNotificationCenter.current().add(notifRequest)
}
```

**Notification philosophy**: Silent by default (no sound). The menu bar badge is the primary signal. The system notification is a secondary channel for when the user isn't looking at the menu bar. The user can disable notifications in System Settings without losing menu bar functionality.

### 2.6 Phase 2 Model Changes Summary

| File | Change |
|------|--------|
| `ManifoldKit/AccessRequest.swift` | **New.** `AccessRequest` type + `BatchedAccessRequest` |
| `ManifoldKit/RequestStore.swift` | **New.** SQLite-backed request queue with batching, expiry |
| `Sources/ManifoldMCP/ManifoldBridge.swift` | Add `handleAccessDenied()` with rate-limiting and batching |
| `ManifoldApp/Models/ManifoldStore.swift` | Add `recentTrustEvents`, `denyAccessRequest()`, wire `RequestStore` |
| `ManifoldApp/Models/PolicyModel.swift` | No changes — approvals open Review sheet, which already updates policy |
| `ManifoldKit/ReviewAccessChange.swift` | Add `.approveRequest(id)` kind with pre-selected sources/domains |

---

## Phase 3: System Extensions + App Intents

### 3.0 Architecture Overview

Phase 3 adds three new targets to the Xcode project:

```
ManifoldApp (main app)
├── ManifoldKit (shared framework)
├── ManifoldMCP (MCP server)
├── ManifoldFinderSync (Finder Sync Extension)     ← Phase 3 new
├── ManifoldMailAction (MailKit Extension)          ← Phase 3 new
└── ManifoldIntents (App Intents)                   ← Phase 3 new
```

All three share `ManifoldKit` for types and `PolicyStore` for reading/writing policies. IPC between extensions and the main app uses an App Group container.

### 3.1 App Group + Shared State

```swift
// In ManifoldKit/SharedDefaults.swift (new or updated)

public enum ManifoldAppGroup {
    public static let identifier = "group.com.spatialduality.manifold"
    
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier)!
    }
    
    public static var sharedContainerURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )!
    }
}
```

The SQLite database for `PolicyStore` and `RequestStore` moves to the shared App Group container so extensions can read policy state directly. The main app and extensions share the database with WAL mode for concurrent access.

**Entitlements** (added to main app + all extensions):
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.spatialduality.manifold</string>
</array>
```

### 3.2 Finder Sync Extension

**Purpose**: Right-click a file or folder in Finder → "Add to Claude" / "Add to Codex"

**Target**: `ManifoldFinderSync` — a Finder Sync Extension (not a Finder Action Extension, which is more limited).

```swift
// ManifoldFinderSync/FinderSync.swift

import FinderSync
import ManifoldKit

class FinderSync: FIFinderSync {
    
    override init() {
        super.init()
        // Watch all volumes — we need context menus everywhere
        FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")])
    }
    
    // MARK: - Context Menu
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "Manifold")
        
        // Read current policy state from shared database
        let policyStore = PolicyStore(appGroup: ManifoldAppGroup.identifier)
        let claudePolicy = policyStore.policy(for: .cowork)
        let codexPolicy = policyStore.policy(for: .codex)
        
        // Only show relevant items
        if claudePolicy != nil {
            let claudeItem = NSMenuItem(
                title: "Add to Claude…",
                action: #selector(addToClaude(_:)),
                keyEquivalent: ""
            )
            claudeItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Claude")
            claudeItem.image?.isTemplate = true
            menu.addItem(claudeItem)
        }
        
        if codexPolicy != nil {
            let codexItem = NSMenuItem(
                title: "Add to Codex…",
                action: #selector(addToCodex(_:)),
                keyEquivalent: ""
            )
            menu.addItem(codexItem)
        }
        
        return menu
    }
    
    @objc func addToClaude(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        triggerReviewSheet(items: items, agent: .cowork)
    }
    
    @objc func addToCodex(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        triggerReviewSheet(items: items, agent: .codex)
    }
    
    private func triggerReviewSheet(items: [URL], agent: TargetApp) {
        // Communicate to main app via XPC / distributed notification / URL scheme
        let paths = items.map(\.path).joined(separator: "\n")
        let userInfo: [String: Any] = [
            "action": "addSources",
            "agent": agent.rawValue,
            "paths": paths
        ]
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.spatialduality.manifold.addSources"),
            object: nil,
            userInfo: userInfo as [AnyHashable: Any],
            deliverImmediately: true
        )
    }
}
```

**Main app receiver** (in `ManifoldStore` or `ManifoldApp`):

```swift
// Listen for Finder extension requests
DistributedNotificationCenter.default().addObserver(
    forName: .init("com.spatialduality.manifold.addSources"),
    object: nil,
    queue: .main
) { notification in
    guard let info = notification.userInfo,
          let agentRaw = info["agent"] as? String,
          let agent = TargetApp(rawValue: agentRaw),
          let paths = info["paths"] as? String else { return }
    
    let urls = paths.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    
    NSApp.activate(ignoringOtherApps: true)
    store.reviewSheetTrigger = ReviewAccessChange(
        description: "Add \(urls.count) item(s) to \(agent.displayName)",
        kind: .addSourcesFromFinder(urls),
        targetAgent: agent
    )
}
```

**The Finder action always opens the Review sheet.** This preserves the product rule that all broadening goes through the Review & Update Access sheet. The Finder extension is a convenient entry point, not a policy bypass.

### 3.3 Finder Sync — Badge Overlays

Finder Sync extensions can also show badge overlays on files/folders. Use this to indicate which folders are shared with which agent:

```swift
override func requestBadgeIdentifier(for url: URL) {
    let policyStore = PolicyStore(appGroup: ManifoldAppGroup.identifier)
    
    let claudeHasAccess = policyStore.policy(for: .cowork)?.allowedSourceIDs
        .contains(where: { sourceID in
            // Check if url is within this source's path
            policyStore.sourcePath(for: sourceID)?.isParent(of: url) == true
        }) ?? false
    
    let codexHasAccess = policyStore.policy(for: .codex)?.allowedSourceIDs
        .contains(where: { sourceID in
            policyStore.sourcePath(for: sourceID)?.isParent(of: url) == true
        }) ?? false
    
    if claudeHasAccess && codexHasAccess {
        FIFinderSyncController.default().setBadgeIdentifier("both", for: url)
    } else if claudeHasAccess {
        FIFinderSyncController.default().setBadgeIdentifier("claude", for: url)
    } else if codexHasAccess {
        FIFinderSyncController.default().setBadgeIdentifier("codex", for: url)
    }
    // No badge for unshared folders
}

override func beginObservingDirectory(at url: URL) {
    // Called when Finder displays a directory we're watching
}
```

Register badges in `init()`:
```swift
FIFinderSyncController.default().setBadgeImage(
    NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Claude")!
        .withSymbolConfiguration(.init(paletteColors: [.systemBlue]))!,
    label: "Shared with Claude",
    forBadgeIdentifier: "claude"
)
// Similar for "codex" (purple) and "both" (blue+purple)
```

### 3.4 MailKit Extension

**Purpose**: View a message in Mail → toolbar action "Add sender's domain to Claude/Codex"

MailKit (introduced macOS 12) supports `ComposeMessageAction` and `MessageAction` extensions. For Manifold, a `MessageAction` extension is the right fit — it adds a toolbar button or action to the message viewer.

```swift
// ManifoldMailAction/ManifoldMailAction.swift

import MailKit
import ManifoldKit

final class ManifoldMailAction: MEMessageAction {
    
    static var actionHandler: ManifoldMailAction { ManifoldMailAction() }
    
    override func decideAction(
        for message: MEMessage,
        completionHandler: @escaping (MEMessageActionDecision) -> Void
    ) {
        // Show the action on all messages
        completionHandler(.invokeAgainWithBody)
    }
    
    override func perform(
        for message: MEMessage,
        body messageBody: MEMessageBody?,
        completionHandler: @escaping (MEMessageActionDecision) -> Void
    ) {
        // Extract sender domain
        guard let sender = message.fromAddress,
              let domain = sender.rawAddress.split(separator: "@").last else {
            completionHandler(.none)
            return
        }
        
        // Trigger Review sheet in main app
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.spatialduality.manifold.addEmailDomain"),
            object: nil,
            userInfo: [
                "domain": String(domain),
                "agent": TargetApp.cowork.rawValue  // default to Claude, can be changed in Review sheet
            ] as [AnyHashable: Any],
            deliverImmediately: true
        )
        
        completionHandler(.none)
    }
}
```

**MailKit limitation**: MailKit is more restrictive than Finder Sync. The extension runs in a sandbox and can only communicate with the main app via IPC (distributed notifications, XPC, or URL scheme). The UX is: user sees a "Share with Manifold" button in Mail's toolbar → clicks it → Manifold's main window comes forward with the Review sheet pre-populated with that domain.

**Registration**: The MailKit extension is registered via the app's `Info.plist` with the `MEComposeSession` and `MEMessageActionHandler` protocols.

### 3.5 App Intents

**Purpose**: Expose Manifold's highest-value actions to Spotlight, Shortcuts, and Siri.

Apple's guidance: expose only the highest-value actions. For Manifold, the right starting set:

```swift
// ManifoldIntents/PauseAllAccessIntent.swift

import AppIntents
import ManifoldKit

struct PauseAllAccessIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause All AI Access"
    static var description = IntentDescription("Immediately suspends all AI agent access to files and emails.")
    static var openAppWhenRun = false
    
    func perform() async throws -> some IntentResult {
        let policyStore = PolicyStore(appGroup: ManifoldAppGroup.identifier)
        await policyStore.pauseAllAgents()
        return .result(dialog: "All AI access has been paused.")
    }
}
```

```swift
// ManifoldIntents/ResumeAccessIntent.swift

struct ResumeAccessIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume AI Access"
    static var description = IntentDescription("Resumes AI agent access that was previously paused.")
    
    @Parameter(title: "Agent")
    var agent: AgentParameter
    
    static var openAppWhenRun = false
    
    func perform() async throws -> some IntentResult {
        let policyStore = PolicyStore(appGroup: ManifoldAppGroup.identifier)
        await policyStore.resumeAgent(agent.targetApp)
        return .result(dialog: "\(agent.displayName) access has been resumed.")
    }
}
```

```swift
// ManifoldIntents/StartWorkBlockIntent.swift

struct StartWorkBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Tracked Work Block"
    static var description = IntentDescription("Opens Manifold to start a tracked work block with change monitoring.")
    static var openAppWhenRun = true  // Must open app — needs Review sheet
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            // Trigger the Review sheet flow
            NotificationCenter.default.post(
                name: .manifoldStartWorkBlockFromIntent,
                object: nil
            )
        }
        return .result()
    }
}
```

```swift
// ManifoldIntents/OpenAuditTrailIntent.swift

struct OpenAuditTrailIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Audit Trail"
    static var description = IntentDescription("Opens Manifold's activity drawer showing recent AI actions.")
    static var openAppWhenRun = true
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .manifoldOpenActivityFromIntent,
                object: nil
            )
        }
        return .result()
    }
}
```

**App Shortcuts Provider** (makes intents discoverable in Spotlight and Shortcuts without user configuration):

```swift
struct ManifoldShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseAllAccessIntent(),
            phrases: [
                "Pause all AI access in \(.applicationName)",
                "Stop AI access in \(.applicationName)"
            ],
            shortTitle: "Pause AI Access",
            systemImageName: "shield.slash"
        )
        
        AppShortcut(
            intent: StartWorkBlockIntent(),
            phrases: [
                "Start a tracked work block in \(.applicationName)"
            ],
            shortTitle: "Track Changes",
            systemImageName: "timeline.selection"
        )
        
        AppShortcut(
            intent: OpenAuditTrailIntent(),
            phrases: [
                "Show AI activity in \(.applicationName)"
            ],
            shortTitle: "AI Activity",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
```

**Total App Intents surface**:

| Intent | Opens App | Needs Review Sheet |
|--------|-----------|-------------------|
| Pause All AI Access | No | No (narrowing) |
| Resume AI Access | No | No (resuming = restoring previous policy, not broadening) |
| Start Tracked Work Block | Yes | Yes |
| Open Audit Trail | Yes | No |

Note: There is no "Grant access to X" intent. Broadening always requires the Review sheet, which requires visual confirmation. You can't grant access via voice command or Shortcut automation because that would violate the intentionality rule in the current product model.

### 3.6 Phase 3 Implementation Notes

**Xcode project changes**:
- Add 3 new targets: ManifoldFinderSync, ManifoldMailAction, ManifoldIntents
- All targets link ManifoldKit
- All targets share the App Group entitlement
- Main app target embeds the extensions

**Database migration**: Move the SQLite database from the app's container to the App Group container. Add a migration path that copies the database on first launch after the update.

**Testing**: Finder Sync and MailKit extensions are notoriously difficult to debug. Use `pluginkit -m` to verify registration. Test with `NSLog` initially, then move to `os_log`.

---

## Implementation Order

```
Phase 1    →  6 hours   →  Menu bar panel: icon, header, agent cards, work block strip,
                            quick actions, empty states. Replace legacy session-model
                            menu bar with the current product model.

Phase 2    →  12 hours  →  Approval queue: AccessRequest model, RequestStore, bridge
                            integration, batching, menu bar UI, system notifications,
                            recent activity feed. Review sheet pre-population from
                            approval flow.

Phase 3    →  16 hours  →  Finder Sync Extension (context menu + badge overlays),
                            MailKit Extension (domain quick-add), App Intents (4 intents),
                            App Group container migration, IPC via distributed notifications.
```

Total: ~34 hours across all three phases.

**Phase 1 is self-contained** and can ship independently. It replaces the broken legacy menu bar with a useful status panel aligned to the current product model.

**Phase 2 depends on Phase 1** (the queue renders in the menu bar panel) and requires MCP bridge changes.

**Phase 3 depends on Phase 2** (Finder/Mail actions may generate access requests that flow into the approval queue) and requires new Xcode targets + entitlements.

---

## What This Spec Does NOT Do

- No custom Liquid Glass on content rows (glass is on the panel chrome only, handled by system)
- No inline policy editing in the menu bar (all broadening goes through Review sheet)
- No "session" language anywhere
- No agent access via Siri/Shortcuts without visual confirmation (broadening intents open the app)
- No notification sounds by default (menu bar badge is the primary signal)
- No per-file grant from Finder (Finder action adds the parent source, which opens Review sheet)

---

## Design Constraints Checklist

From v2 APPLE-DESIGN-EXCELLENCE-GUIDE:
1. ✅ Glass on chrome only (system menu bar extra window handles this)
2. ✅ Named spring presets for any animation
3. ✅ System transitions for panels
4. ✅ No backgroundExtensionEffect
5. ✅ Accessibility labels on all controls

From the April 13 product spec:
1. ✅ Current model: Standing Access + Optional Tracked Work Blocks
2. ✅ No "session" language
3. ✅ All broadening through Review & Update Access sheet
4. ✅ Pause Access as button, not toggle
5. ✅ "Work Block" language throughout
6. ✅ Sensitivity not exposed in menu bar (it's a Domains toolbar control)

From research conclusions:
1. ✅ Single compact icon, not wordmark
2. ✅ Five questions answerable instantly
3. ✅ Panic control always visible
4. ✅ Fixed section order for spatial memory
5. ✅ Complex flows open main app (Tailscale lesson)
6. ✅ Phase 3 covers Finder, Mail, and App Intents
