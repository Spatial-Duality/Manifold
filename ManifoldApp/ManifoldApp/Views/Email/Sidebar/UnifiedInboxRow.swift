// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct UnifiedInboxRow: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    @State private var unreadCount: Int = 0

    var body: some View {
        Section {
            Button {
                selection.navigate(accountID: nil)
            } label: {
                Label {
                    HStack {
                        Text("All Inboxes")
                        Spacer()
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.blue, in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "tray.2.fill")
                        .foregroundStyle(.blue)
                }
            }
            .buttonStyle(.plain)
            .fontWeight(selection.selectedAccountID == nil && selection.activeFilter == nil && !selection.showingSharedEmails ? .semibold : .regular)
        }
        .task {
            unreadCount = await store.emailAccounts.unreadCountAll()
        }
    }
}
