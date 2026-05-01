// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Builds the menu bar mark — just the {|}, no background. The
/// underlying SF Symbol is sized so its cap-height portion fills the
/// full menu-bar height (instead of the typographic ~85% it would get
/// at default sizing), so the brackets read at the same visual scale
/// as filled neighbouring icons.
///
/// Math: our custom symbol has cap-height = 70 units and total bounding
/// box (cap → descender) = 83 units. To put the visible bracket cap at
/// 22pt, the NSImage size needs to be 22 × (83/70) ≈ 26pt.
@MainActor
private func menuBarBrandImage() -> NSImage {
    guard let original = NSImage(named: "Manifold Icon SF") else {
        let fallback = NSImage(systemSymbolName: "curlybraces",
                               accessibilityDescription: "Manifold")
            ?? NSImage(size: NSSize(width: 22, height: 22))
        fallback.isTemplate = true
        return fallback
    }
    let sized = original.copy() as! NSImage
    sized.size = NSSize(width: 26, height: 26)
    sized.isTemplate = true
    return sized
}

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
                if let command = commandPalette.command(.startSession, for: store) {
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
                ForEach([ManifoldCommandID.openWork, .openAccess, .openMail, .openRules], id: \.self) { commandID in
                    if let command = commandPalette.command(commandID, for: store) {
                        Button(command.title) {
                            Task { await command.action(store) }
                        }
                        .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
                    }
                }
                Divider()
                if let command = commandPalette.command(.startSession, for: store) {
                    Button(command.title) {
                        Task { await command.action(store) }
                    }
                    .keyboardShortcut(command.shortcut!.key, modifiers: command.shortcut!.modifiers)
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

            CommandGroup(replacing: .help) {
                Button("Manifold Help") {
                    if let url = URL(string: "https://github.com/amargandhi/Manifold") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                if let updater = store.updater {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    Divider()
                }
                Button("Reveal Diagnostics in Finder") {
                    store.diagnostics.revealDiagnosticsInFinder()
                }
                Button("Create Diagnostic Report…") {
                    // Opens Settings; user navigates to Advanced -> Diagnostics.
                    // A future iteration can deep-link to the Diagnostics
                    // section directly via a SceneStorage selection.
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NotificationCenter.default.post(name: .manifoldOpenSettingsDiagnostics, object: nil)
                }
            }
        }

        // Custom Manifold mark in the menu bar.
        //
        // We use the `content:label:` form (not `image:`) and load the
        // asset catalog symbol via NSImage so we can set an explicit
        // pixel size. The default `MenuBarExtra(image:)` sizes the
        // symbol to its cap height (~14pt), which makes the mark read
        // smaller than filled menu-bar icons (Codex, ChatGPT) that span
        // the full ~18-22pt status bar height. Setting NSImage.size
        // explicitly overrides that, so the mark visually matches its
        // neighbours.
        //
        // The rendered icon preserves the store-driven badge states, so
        // pending approvals, pause, and disconnected runtime states stay
        // visible from the menu bar.
        MenuBarExtra {
            MenuBarPanelView()
                .environment(store)
                .environment(commandPalette)
        } label: {
            Image(nsImage: menuBarImage())
                .accessibilityLabel("Manifold")
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
            case .syntheticMCPUI: .syntheticMCPUI
            }
            let runtime = FixtureRuntimeClient(profile: profile)
            let health = IntegrationHealthModel(checker: FixtureIntegrationHealthChecker(profile: profile))
            let store = ManifoldStore(runtime: runtime, integrationHealth: health, startServices: false)
            store.setup.hasCompletedOnboarding = true
            return store
        }
    }

    @MainActor
    private func menuBarImage() -> NSImage {
        MenuBarBrandIcon.renderTemplateImage(state: store.menuBarBadgeState)
            ?? menuBarBrandImage()
    }
}
