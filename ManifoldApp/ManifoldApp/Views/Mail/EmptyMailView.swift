// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct EmptyMailView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var addAccountSheetPresented = false

    var body: some View {
        // Same composition as EmptyFoldersView: the app's own
        // EmptyStateIllustration (purpose-built .mail style) over a
        // large-control CTA, instead of the system ContentUnavailableView.
        VStack(spacing: Spacing.s6) {
            EmptyStateIllustration(
                systemImage: "tray.2",
                title: "No mailboxes connected",
                subtitle: "Connect a mailbox so you can review backed-up mail and share individual messages with confidence.",
                tint: ManifoldPalette.selection,
                style: .mail
            )

            Button {
                addAccountSheetPresented = true
            } label: {
                Label("Connect mailbox\u{2026}", systemImage: "plus")
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("mail.empty.connectMailbox")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
        .background(ManifoldPalette.bg)
        .accessibilityIdentifier("mail.empty")
        .sheet(isPresented: $addAccountSheetPresented) {
            AddMailAccountSheet()
                .environment(store)
        }
    }
}
