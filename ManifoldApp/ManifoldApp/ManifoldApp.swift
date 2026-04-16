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
            RootWindowContent()
                .environment(store)
                .environment(commands)
                .frame(minWidth: 920, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Session\u{2026}") {
                    NotificationCenter.default.post(name: .manifoldShowSessionStartSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Add Folder\u{2026}") {
                    store.addSourceFromPicker()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    commands.isPresented.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Activity") {
                    focusLedger()
                }
                .keyboardShortcut("1", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo Last Action") {
                    Task { await store.policy.undoLastAction() }
                }
                .keyboardShortcut("z", modifiers: .command)
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

    private func focusLedger() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
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
