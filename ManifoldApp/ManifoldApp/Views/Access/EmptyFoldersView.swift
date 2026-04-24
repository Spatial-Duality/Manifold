// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyFoldersView — the Access surface with zero shared sources.
//
// Folders-only CTA per Stage 5 decision (mailbox share is its own
// surface). Calm, not celebratory: an empty access ledger is the
// default state, not an onboarding milestone.

import SwiftUI

struct EmptyFoldersView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        VStack(spacing: Spacing.s6) {
            EmptyStateIllustration(
                systemImage: "folder.badge.plus",
                title: "Nothing shared yet",
                subtitle: "Nothing is shared until you share it. Add a folder to let an agent read inside a session. Mail is a separate surface.",
                tint: ManifoldPalette.selection,
                style: .access
            )

            HStack(spacing: Spacing.s2) {
                Button {
                    store.addSourceFromPicker()
                } label: {
                    Label("Add a folder\u{2026}", systemImage: "folder.badge.plus")
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s1)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .accessibilityIdentifier("access.empty.addFolder")

                Button {
                    store.addFilesFromPicker()
                } label: {
                    Label("Add files\u{2026}", systemImage: "doc.badge.plus")
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s1)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("access.empty.addFiles")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
        .background(ManifoldPalette.bg)
        .accessibilityIdentifier("access.empty")
    }
}
