import SwiftUI
import ManifoldKit

@main
struct ManifoldApp: App {
    @State private var store = ManifoldStore()
    @State private var commands = CommandCenter()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environment(store)
                .environment(commands)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    commands.isPresented.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Overview") { store.selectedTab = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Files") { store.selectedTab = .files }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Emails") { store.selectedTab = .emails }
                    .keyboardShortcut("3", modifiers: .command)
            }

            CommandMenu("Access") {
                Button("Review Access\u{2026}") {
                    store.reviewSheetTrigger = ReviewAccessChange(
                        description: "Review access",
                        kind: .explicit
                    )
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Track Changes") {
                    store.reviewSheetTrigger = ReviewAccessChange(
                        description: "Start tracking changes",
                        kind: .startWorkBlock
                    )
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button(pauseLabel) {
                    Task {
                        let agent: TargetApp = store.agentFocus == .codex ? .codex : .cowork
                        let policy = store.policy.policy(for: agent)
                        if policy?.isPaused == true {
                            await store.policy.resumeAgent(agent)
                        } else {
                            await store.policy.pauseAgent(agent)
                        }
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Activity") {
                    store.showActivityDrawer.toggle()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    if store.inspectedFilePath != nil {
                        store.inspectedFilePath = nil
                    }
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("Add Source\u{2026}") {
                    store.addSourceFromPicker()
                }
            }
        }

        MenuBarExtra("Manifold", systemImage: store.menuBarIcon) {
            menuBarContent
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }

    private var pauseLabel: String {
        let agent: TargetApp = store.agentFocus == .codex ? .codex : .cowork
        let policy = store.policy.policy(for: agent)
        return policy?.isPaused == true ? "Resume Access" : "Pause Access"
    }

    // MARK: - Menu Bar Content

    @ViewBuilder
    private var menuBarContent: some View {
        // Zone 1: Session + Connection
        sessionSection
        Divider()
        connectionSection
        Divider()

        // Zone 2: Quick Sources
        sourcesSection
        Divider()

        // Zone 3: Navigation
        Button("Open Manifold") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("o")

        Button("Settings...") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Manifold") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var sessionSection: some View {
        if store.hasActiveSession {
            Label("Session Active", systemImage: "circle.fill")
                .foregroundStyle(.green)
            if store.activeGrant != nil {
                Text("\(store.activeGrantSources.count) sources")
            }
            Button("End Session") {
                Task { await store.endSession() }
            }
        } else {
            Label("No Active Session", systemImage: "circle")
            if !store.approvedSources.isEmpty {
                Text("\(store.approvedSources.count) sources ready")
                Button("Start Session") {
                    Task { await store.startSession() }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        if store.isConnected, let agent = store.connectedAgent {
            Label("\(agent) connected", systemImage: "antenna.radiowaves.left.and.right")
        } else {
            Label("No agents", systemImage: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        let visible = store.sources.filter { !$0.isRemoved }
        if visible.isEmpty {
            Text("No sources added")
                .foregroundStyle(.secondary)
        } else {
            Text("Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(visible) { source in
                Button {
                    Task {
                        if source.isAccessible {
                            await store.pauseSource(sourceID: source.sourceID)
                        } else {
                            await store.resumeSource(sourceID: source.sourceID)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: source.isAccessible ? "folder.fill" : "folder")
                        Text(source.displayName)
                        Spacer()
                        Text(source.isAccessible ? "Active" : "Paused")
                            .foregroundStyle(source.isAccessible ? .primary : .secondary)
                    }
                }
            }
        }
    }
}
