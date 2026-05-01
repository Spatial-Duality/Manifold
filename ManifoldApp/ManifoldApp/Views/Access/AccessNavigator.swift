// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AccessNavigator: View {
    @Environment(ManifoldStore.self) private var store
    @Binding var selection: AccessSection

    var body: some View {
        List(selection: $selection) {
            Section("Access") {
                ForEach(AccessSection.allCases) { section in
                    Label(section.label, systemImage: section.systemImage)
                        .tag(section)
                        .disabled(section == .session && store.activeSession == nil)
                        .accessibilityIdentifier("access.sidebar.\(section.rawValue)")
                }
            }

            Section("Manage") {
                Button {
                    if store.addSourceFromPicker() {
                        selection = .folders
                    }
                } label: {
                    Label("Add folder", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .accessibilityIdentifier("access.addFolder")

                Button {
                    if store.addFilesFromPicker() {
                        selection = .files
                    }
                } label: {
                    Label("Add files", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("access.addFiles")
            }
        }
        .listStyle(.sidebar)
        .onChange(of: store.activeSession?.id) { _, activeSessionID in
            if activeSessionID == nil, selection == .session {
                selection = .folders
            }
        }
        .accessibilityIdentifier("access.sidebar")
    }
}
