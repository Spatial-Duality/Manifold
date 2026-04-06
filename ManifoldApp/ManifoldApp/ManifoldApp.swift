import SwiftUI

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

                Button("Home") { store.selectedSidebarItem = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Files") { store.selectedSidebarItem = .files }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Emails") { store.selectedSidebarItem = .emails }
                    .keyboardShortcut("3", modifiers: .command)
                Button("History") { store.selectedSidebarItem = .history }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Sources") { store.selectedSidebarItem = .sources }
                    .keyboardShortcut("5", modifiers: .command)
            }

            CommandMenu("Session") {
                Button("Start Session") {
                    Task { await store.startSession() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.hasActiveSession || store.approvedSources.isEmpty)

                Button("End Session") {
                    Task { await store.endSession() }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!store.hasActiveSession)

                Divider()

                Button("Add Source...") {
                    store.addSourceFromPicker()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Manifold", systemImage: store.menuBarIcon) {
            menuBarContent
        }

        Settings {
            SetupView()
                .environment(store)
                .frame(minWidth: 520, minHeight: 420)
        }
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
                Text("\(store.activeGrantSources.count) sources \u{00B7} \(store.selectedEmailIDsForNextSession.count) emails")
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
