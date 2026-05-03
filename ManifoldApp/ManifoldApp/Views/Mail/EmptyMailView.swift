// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct EmptyMailView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var addAccountSheetPresented = false

    var body: some View {
        ContentUnavailableView {
            Label("No mailboxes connected", systemImage: "tray.2")
        } description: {
            Text("Connect a mailbox so you can review backed-up mail and share individual messages with confidence.")
        } actions: {
            Button("Connect Mailbox…", systemImage: "plus") {
                addAccountSheetPresented = true
            }
            .accessibilityIdentifier("mail.empty.connectMailbox")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("mail.empty")
        .sheet(isPresented: $addAccountSheetPresented) {
            AddMailAccountSheet()
                .environment(store)
        }
    }
}
