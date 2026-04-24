// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

@MainActor
func presentMainLedger(destination: LedgerDestination? = nil) {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
        window.makeKeyAndOrderFront(nil)
    }
    if let destination {
        NotificationCenter.default.post(name: .manifoldShowLedgerDestination, object: destination.rawValue)
    }
}

@main
struct ManifoldApp: App {
    @State private var store: ManifoldStore
    @State private var commandPalette = CommandPaletteModel()

    init() {
        _store = State(initialValue: Self.bootstrapStore())
    }

    var body: some Scene {
        Window("Manifold", id: "main") {
            AppRootView()
                .environment(store)
                .environment(commandPalette)
                .frame(minWidth: 920, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                if let command = commandPalette.command(.protectNextSession, for: store) {
                    Button(command.title) {
                        Task { await command.action(store) }
                    }
                    .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
                }

                if let command = commandPalette.command(.addFolder, for: store) {
                    Button(command.title) {
                        Task { await command.action(store) }
                    }
                    .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
                }
            }

            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    commandPalette.isPresented.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                if let command = commandPalette.command(.openSessionRecap, for: store) {
                    Button(command.title) {
                        Task { await command.action(store) }
                    }
                }

                if let command = commandPalette.command(.refreshRuntime, for: store) {
                    Button(command.title) {
                        Task { await command.action(store) }
                    }
                    .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
                }
            }

            CommandMenu("View") {
                ForEach([ManifoldCommandID.openActivity, .openAccess, .openMail, .openRequests], id: \.self) { commandID in
                    if let command = commandPalette.command(commandID, for: store) {
                        Button(command.title) {
                            Task { await command.action(store) }
                        }
                        .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
                    }
                }

                Divider()

                Button("Previous Section") {
                    NotificationCenter.default.post(name: .manifoldCycleCurrentSubtab, object: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button("Next Section") {
                    NotificationCenter.default.post(name: .manifoldCycleCurrentSubtab, object: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }

            CommandMenu("Find") {
                Button("Find in Current View") {
                    NotificationCenter.default.post(name: .manifoldFocusCurrentSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
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
                .environment(commandPalette)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
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
            return store
        case .localRuntime(let scenario):
            let profile: AppFixtureProfile = switch scenario {
            case .privacyE2E: .runtimePrivacy
            }
            let runtime = FixtureRuntimeClient(profile: profile)
            let health = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: profile))
            let store = ManifoldStore(runtime: runtime, integrationHealth: health, startServices: false)
            store.setup.hasCompletedOnboarding = true
            return store
        }
    }
}
