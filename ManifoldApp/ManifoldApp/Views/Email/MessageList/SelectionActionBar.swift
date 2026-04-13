// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct SelectionActionBar: View {
    @Environment(ManifoldStore.self) var store
    let selectedCount: Int
    @Bindable var selection: EmailSelectionModel
    @State private var showShareSheet = false

    var body: some View {
        HStack(spacing: Spacing.section) {
            Text("\(selectedCount) selected")
                .font(.callout.weight(.medium))

            Spacer()

            Button {
                showShareSheet = true
            } label: {
                Label("Share with Claude", systemImage: "person.2.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.small)

            Menu {
                Button {
                    Task {
                        await store.emailAccounts.batchUpdateReadState(
                            emailIDs: Array(selection.selectedMessageIDs), isRead: true
                        )
                    }
                } label: {
                    Label("Mark as Read", systemImage: "envelope.open")
                }
                Button {
                    Task {
                        await store.emailAccounts.batchUpdateReadState(
                            emailIDs: Array(selection.selectedMessageIDs), isRead: false
                        )
                    }
                } label: {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
                Divider()
                Button {
                    Task {
                        await store.emailAccounts.batchUpdateFlagState(
                            emailIDs: Array(selection.selectedMessageIDs), isFlagged: true
                        )
                    }
                } label: {
                    Label("Flag", systemImage: "flag.fill")
                }
                Button {
                    Task {
                        await store.emailAccounts.batchUpdateFlagState(
                            emailIDs: Array(selection.selectedMessageIDs), isFlagged: false
                        )
                    }
                } label: {
                    Label("Unflag", systemImage: "flag.slash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.standard)
        .background(.bar)
        .sheet(isPresented: $showShareSheet) {
            ShareWithCoworkSheet(
                emailIDs: Array(selection.selectedMessageIDs),
                onDismiss: { showShareSheet = false }
            )
        }
    }
}
