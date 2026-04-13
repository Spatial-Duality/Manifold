// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Synology Active Backup–style governance browser table.
/// Full-width table with checkboxes, domain column, and inline preview on click.
/// NOT a mail client. Focus: selection, search, bulk operations, access control.
struct EmailMessageList: View {
    @Environment(ManifoldStore.self) var store
    @Bindable var selection: EmailSelectionModel
    @Bindable var search: EmailSearchModel
    let messages: [EmailMessageRecord]

    @State private var selectedIDs: Set<String> = []
    @State private var previewingMessageID: String?
    @State private var searchText = ""
    @State private var sharedEmailIDs: Set<String> = []

    private var focusedAgent: TargetApp {
        store.agentFocus.targetApp
    }

    private var filteredMessages: [EmailMessageRecord] {
        if searchText.isEmpty { return messages }
        return messages.filter {
            $0.sender.localizedStandardContains(searchText) ||
            $0.subject.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: search + bulk actions + agent focus
            toolbar

            // Message rows with inline preview
            if filteredMessages.isEmpty {
                emptyState
            } else {
                messageList
            }

            // Footer
            footer
        }
        .task { sharedEmailIDs = await store.emailAccounts.sharedEmailIDs() }
    }

    private func isShared(_ message: EmailMessageRecord) -> Bool {
        sharedEmailIDs.contains(message.emailID)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            TextField("Search by sender, subject\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 320)

            // Bulk actions (when items selected)
            if !selectedIDs.isEmpty {
                HStack(spacing: 8) {
                    Text("^[\(selectedIDs.count) selected](inflect: true)")
                        .font(Typ.caption)
                        .fontWeight(.medium)

                    Button("Share with \(focusedAgent == .codex ? "Codex" : "Claude")", systemImage: "shield") {
                        Task {
                            await store.emailAccounts.shareEmails(emailIDs: Array(selectedIDs))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.agent(focusedAgent))
                    .controlSize(.small)

                    Button("Export", systemImage: "arrow.down.circle") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Spacer()

            AgentFocusControl(focus: Binding(
                get: { store.agentFocus },
                set: { store.agentFocus = $0 }
            ))
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.standard)
        .background(.bar)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    // Select all checkbox
                    Button {
                        if allSelected {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(filteredMessages.map(\.emailID))
                        }
                    } label: {
                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(allSelected ? Color.agent(focusedAgent) : Color.gray)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36)

                    Text("From").font(Typ.caption).fontWeight(.semibold).frame(minWidth: 100, alignment: .leading)
                    Text("Subject").font(Typ.caption).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Domain").font(Typ.caption).fontWeight(.semibold).frame(width: 100, alignment: .leading)
                    Text("Date").font(Typ.caption).fontWeight(.semibold).frame(width: 80, alignment: .trailing)
                    Image(systemName: "paperclip").font(.caption).foregroundStyle(.tertiary).frame(width: 40)
                    Text("Shared").font(Typ.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.agent(focusedAgent))
                        .frame(width: 70, alignment: .center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.bar)

                Divider()

                // Message rows
                ForEach(filteredMessages) { message in
                    VStack(spacing: 0) {
                        messageRow(message)

                        // Inline preview (Synology pattern)
                        if previewingMessageID == message.emailID {
                            InlineMessagePreview(
                                message: message,
                                focusedAgent: focusedAgent,
                                onClose: { withAnimation(Anim.structural) { previewingMessageID = nil } }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Message Row

    private func messageRow(_ message: EmailMessageRecord) -> some View {
        let isSelected = selectedIDs.contains(message.emailID)
        let isPreviewing = previewingMessageID == message.emailID

        return HStack(spacing: 0) {
            // Checkbox
            Button {
                if selectedIDs.contains(message.emailID) {
                    selectedIDs.remove(message.emailID)
                } else {
                    selectedIDs.insert(message.emailID)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.agent(focusedAgent) : Color.gray)
            }
            .buttonStyle(.plain)
            .frame(width: 36)

            // From
            Text(senderName(message.sender))
                .font(Typ.body)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(minWidth: 100, alignment: .leading)

            // Subject
            Text(message.subject)
                .font(Typ.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)

            // Domain
            Text("@\(message.senderDomain ?? senderDomain(message.sender))")
                .font(Typ.mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            // Date
            Text(message.receivedAt.prefix(10))
                .font(Typ.numericCaption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            // Attachment
            Group {
                if message.attachmentCount > 0 {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Color.clear
                }
            }
            .frame(width: 40)

            // Shared status
            Group {
                if isShared(message) {
                    Circle()
                        .fill(Color.agent(focusedAgent))
                        .frame(width: 8, height: 8)
                } else {
                    Text("\u{2014}")
                        .font(Typ.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            isPreviewing ? Color.accentColor.opacity(0.06)
            : isShared(message) ? Color.agent(focusedAgent).opacity(Opacity.rowTint)
            : Color.clear
        )
        .onTapGesture {
            withAnimation(Anim.structural) {
                previewingMessageID = isPreviewing ? nil : message.emailID
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if !searchText.isEmpty {
                ContentUnavailableView {
                    Label("No results for \"\(searchText)\"", systemImage: "envelope")
                } description: {
                    Text("Try a different search term or clear filters.")
                }
            } else if !store.isRuntimeConnected {
                ContentUnavailableView {
                    Label("Runtime Disconnected", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text("Reconnect the Manifold runtime to load this mailbox.")
                }
            } else if store.emailAccounts.isSyncing {
                VStack(spacing: Spacing.standard) {
                    ProgressView()
                    Text("Syncing messages\u{2026}")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Messages", systemImage: "envelope")
                } description: {
                    Text("This mailbox is empty.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("^[\(filteredMessages.count) message](inflect: true)")
                .font(Typ.caption)
            if !selectedIDs.isEmpty {
                Text("\u{00B7} \(selectedIDs.count) selected")
                    .font(Typ.caption)
            }
            Spacer()
            Text("Last synced: 2 min ago")
                .font(Typ.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Helpers

    private var allSelected: Bool {
        !filteredMessages.isEmpty && filteredMessages.allSatisfy { selectedIDs.contains($0.emailID) }
    }

    private func senderName(_ sender: String) -> String {
        if let angle = sender.firstIndex(of: "<") {
            let name = String(sender[..<angle]).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? sender : name
        }
        return sender
    }

    private func senderDomain(_ sender: String) -> String {
        if let atSign = sender.lastIndex(of: "@") {
            let domain = String(sender[sender.index(after: atSign)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "> "))
            return domain
        }
        return ""
    }
}
