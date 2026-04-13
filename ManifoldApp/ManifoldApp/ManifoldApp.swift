// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

@main
struct ManifoldApp: App {
    @State private var store: ManifoldStore
    @State private var commands = CommandCenter()

    init() {
        _store = State(initialValue: Self.bootstrapStore())
    }

    var body: some Scene {
        Window("Manifold", id: "main") {
            MainView()
                .environment(store)
                .environment(commands)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.automatic)
        .commands {
            // File menu
            CommandGroup(after: .newItem) {
                Button("Add Folder\u{2026}") {
                    store.addSourceFromPicker()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            // View menu
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
                        let agent: TargetApp = store.agentFocus.targetApp
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

            CommandGroup(replacing: .appTermination) {
                Button("Quit Manifold") {
                    store.quitManifold()
                }
                .keyboardShortcut("q")
            }
        }

        MenuBarExtra("Manifold", systemImage: store.menuBarIcon) {
            MenuBarPanelView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }

    private var pauseLabel: String {
        let agent: TargetApp = store.agentFocus.targetApp
        let policy = store.policy.policy(for: agent)
        return policy?.isPaused == true ? "Resume Access" : "Pause Access"
    }

    private static func bootstrapStore() -> ManifoldStore {
        switch AppTestMode.current {
        case .live:
            return ManifoldStore()
        case .fixture(let profile):
            let runtime = FixtureRuntimeClient(profile: profile)
            let health = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: profile))
            let store = ManifoldStore(runtime: runtime, integrationHealth: health, startServices: false)
            store.setup.hasCompletedOnboarding = profile != .onboarding
            if profile == .emailRules {
                store.selectedTab = .emails
                store.agentFocus = .claude
            }
            return store
        }
    }

}
