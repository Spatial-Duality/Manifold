// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct MailSessionView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if let session = store.activeSession {
                    SessionChip(
                        name: session.name,
                        remainingSeconds: session.remainingSeconds,
                        isTrackedEdit: session.isTrackedEdit
                    )
                    Text("Mailbox additions, removals, and inherited scope land here when the mail-session pipeline is wired end to end.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(
                        "No session running",
                        systemImage: "play.circle",
                        description: Text("Mail-scope changes layer on top of the default whenever a session is live.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(Spacing.s4)
        }
    }
}
