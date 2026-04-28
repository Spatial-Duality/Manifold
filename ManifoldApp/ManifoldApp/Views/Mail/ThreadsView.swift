// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailReviewView — Active Backup-style mail review surface.
//
// This is intentionally not a mail client. The left rail scopes the
// backed-up mail, the center table is dense and sortable, and the
// inspector shows only the metadata and safe excerpt needed to make
// atomic allow / hide decisions.

import SwiftUI
import ManifoldKit

struct MailReviewView: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview
    @FocusState private var isSearchFocused: Bool
    @State private var sortOrder = [KeyPathComparator(\MailReviewRow.receivedDate, order: .reverse)]
    /// Inspector hidden by default — opens automatically when the user
    /// clicks a message and can be dismissed via the close button or
    /// the toolbar toggle. Persisted so the user's last choice sticks
    /// across launches.
    @AppStorage("mail.inspector.visible") private var isInspectorVisible: Bool = false

    private var selectedAccount: EmailAccountRecord? {
        guard let accountID = mailReview.selectedAccountID else { return nil }
        return mailAccounts.accounts.first(where: { $0.accountID == accountID })
    }

    private var selectedSyncState: SyncStateRecord? {
        guard let accountID = mailReview.selectedAccountID,
              let mailboxName = mailReview.selectedMailboxName else {
            return nil
        }
        return mailAccounts.syncStates[accountID]?.first(where: { $0.mailboxName == mailboxName })
    }

    private var reviewRows: [MailReviewRow] {
        mailReview.messages.map { message in
            MailReviewRow(
                message: message,
                threadKey: MailThreadRow.threadKey(for: message),
                visibilityState: mailReview.sharedEmailIDs.contains(message.emailID)
                    ? VisibilityState(effective: .allowed, origin: .explicit)
                    : VisibilityState(effective: .hidden, origin: .defaultScope)
            )
        }
        .sorted(using: sortOrder)
    }

    private var selectedMessageBinding: Binding<String?> {
        Binding(
            get: { mailReview.selectedMessageID },
            set: { newValue in
                guard let newValue,
                      let row = reviewRows.first(where: { $0.emailID == newValue }) else {
                    mailReview.selectedMessageID = nil
                    return
                }
                mailReview.selectMessage(row.emailID, threadKey: row.threadKey)
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            MailScopeRail()
                .frame(width: 248)
                .background(ManifoldPalette.surface)

            Divider()

            VStack(spacing: 0) {
                ThreadToolbar(
                    selectedAccount: selectedAccount,
                    selectedMailboxName: mailReview.selectedMailboxName,
                    isSearchFocused: $isSearchFocused,
                    isInspectorVisible: $isInspectorVisible
                )
                Divider()
                MailReviewTableArea(
                    selectedAccount: selectedAccount,
                    selectedSyncState: selectedSyncState,
                    rows: reviewRows,
                    sortOrder: $sortOrder,
                    selection: selectedMessageBinding,
                    onOpenInspector: { isInspectorVisible = true }
                )
            }
            .frame(maxWidth: .infinity)

            if isInspectorVisible {
                Divider()
                ThreadInspector(onClose: { isInspectorVisible = false })
                    .frame(width: 320)
                    .background(ManifoldPalette.surface2)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(ManifoldMotion.micro, value: isInspectorVisible)
        .accessibilityElement(children: .contain)
        .onReceive(NotificationCenter.default.publisher(for: .manifoldFocusCurrentSearch)) { _ in
            isSearchFocused = true
        }
        // Single click selects the row (highlights it) but does NOT open
        // the inspector — that matches the macOS Finder convention. Double
        // click on a row opens the inspector (see openInspectorForRow in
        // MailReviewTableArea). User can also press the toolbar toggle or
        // ⌥⌘0 at any time, regardless of selection.
        .background {
            // ⌥⌘0 toggles the inspector — same chord as the Files inspector.
            Button("Toggle Mail Inspector") { isInspectorVisible.toggle() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

private struct MailScopeRail: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Accounts")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)

                            ForEach(mailAccounts.accounts) { account in
                                ScopeRailButton(
                                    title: account.displayName,
                                    subtitle: account.username ?? account.provider.displayName,
                                    systemImage: account.provider.systemImage,
                                    isSelected: mailReview.selectedAccountID == account.accountID,
                                    accessibilityIdentifier: "mail.account.\(account.accountID)"
                                ) {
                                    Task { await mailReview.selectAccount(account.accountID) }
                                }
                            }
                }

                Divider()

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Mailboxes")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)

                    if let accountID = mailReview.selectedAccountID {
                        let mailboxes = mailReview.mailboxes(for: accountID).filter(\.isSelectable)
                        if mailboxes.isEmpty {
                            Text("No synced mailboxes yet")
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(mailboxes) { mailbox in
                                ScopeRailButton(
                                    title: mailbox.mailboxName,
                                    subtitle: mailbox.folderType.rawValue.capitalized,
                                    systemImage: mailbox.folderType.systemImage,
                                    isSelected: mailReview.selectedMailboxName == mailbox.mailboxName,
                                    accessibilityIdentifier: "mail.mailbox.\(accountID).\(mailbox.mailboxName.replacingOccurrences(of: " ", with: "-"))"
                                ) {
                                    Task { await mailReview.selectMailbox(mailbox.mailboxName) }
                                }
                            }
                        }
                    } else {
                        Text("Pick an account first")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("Quick filters")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)

                    ForEach(QuickFilter.defaultVisible) { filter in
                        ScopeRailButton(
                            title: filter.displayName,
                            subtitle: "Filter the current mailbox",
                            systemImage: filter.systemImage,
                            isSelected: mailReview.activeQuickFilter == filter,
                            accessibilityIdentifier: "mail.quickFilter.\(filter.rawValue)"
                        ) {
                            Task { await mailReview.setQuickFilter(filter) }
                        }
                    }
                }
            }
            .padding(Spacing.s4)
        }
    }
}

private struct ScopeRailButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? ManifoldPalette.selection : ManifoldPalette.text2)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ManifoldType.body)
                    Text(subtitle)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? ManifoldPalette.selectionSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "mail.scope.\(title)")
    }
}

private struct ThreadToolbar: View {
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccount: EmailAccountRecord?
    let selectedMailboxName: String?
    @FocusState.Binding var isSearchFocused: Bool
    @Binding var isInspectorVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s3) {
                TextField(
                    "Search sender, subject, or preview",
                    text: Binding(
                        get: { mailReview.searchText },
                        set: { mailReview.updateSearchText($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .focused($isSearchFocused)
                .accessibilityIdentifier("mail.searchField")

                if let selectedAccount, let selectedMailboxName {
                    Text("\(selectedAccount.displayName) · \(selectedMailboxName)")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Agent", selection: Binding(
                    get: { mailReview.targetAgent },
                    set: { agent in Task { await mailReview.selectTargetAgent(agent) } }
                )) {
                    ForEach(TargetApp.allCases, id: \.self) { agent in
                        Text(AgentMeta.label(agent)).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .accessibilityIdentifier("mail.targetAgent")

                Button("Sync now") {
                    Task { await mailReview.syncSelectedAccount() }
                }
                .buttonStyle(.bordered)
                .disabled(selectedAccount == nil)

                Button {
                    isInspectorVisible.toggle()
                } label: {
                    Image(systemName: isInspectorVisible
                        ? "sidebar.right"
                        : "sidebar.squares.right")
                }
                .buttonStyle(.borderless)
                .help(isInspectorVisible ? "Hide message inspector" : "Show message inspector")
                .keyboardShortcut("0", modifiers: [.command, .option])
                .accessibilityIdentifier("mail.inspector.toggle")
            }

            Text(summaryLine)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(.regularMaterial)
    }

    private var summaryLine: String {
        let threadCount = mailReview.threadRows.count
        let messageCount = mailReview.messages.count
        let sharedCount = mailReview.sharedEmailIDs.intersection(Set(mailReview.messages.map(\.emailID))).count
        return "\(threadCount) conversations · \(messageCount) messages · \(sharedCount) shared with \(AgentMeta.label(mailReview.targetAgent))"
    }
}

private struct MailReviewTableArea: View {
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccount: EmailAccountRecord?
    let selectedSyncState: SyncStateRecord?
    let rows: [MailReviewRow]
    @Binding var sortOrder: [KeyPathComparator<MailReviewRow>]
    @Binding var selection: String?
    let onOpenInspector: () -> Void

    var body: some View {
        if mailReview.isLoading && mailReview.messages.isEmpty {
            ProgressView("Loading backed-up mail…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = mailReview.errorMessage, mailReview.messages.isEmpty {
            ContentUnavailableView(
                "Couldn’t load backed-up mail",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .overlay(alignment: .bottom) {
                Button("Retry") {
                    Task { await mailReview.retry() }
                }
                .buttonStyle(.borderedProminent)
                .padding(Spacing.s5)
            }
        } else if mailReview.selectedMailboxName == nil {
            ContentUnavailableView(
                "No synced mailboxes yet",
                systemImage: "tray",
                description: Text("Run a backup for this account, then come back here to browse individual messages.")
            )
        } else if mailReview.messages.isEmpty {
            EmptyMailboxState(selectedAccount: selectedAccount, selectedSyncState: selectedSyncState)
        } else {
            VStack(spacing: 0) {
                if let banner = syncBannerText {
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(banner)
                            .font(ManifoldType.caption)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s2)
                    .background(ManifoldPalette.attention.opacity(0.12))
                    .foregroundStyle(ManifoldPalette.attention)
                }

                Table(of: MailReviewRow.self, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Share", value: \.visibilitySortKey) { row in
                        // Same checkbox visual as files/folders. Tappable
                        // toggle wired to setMessageShared. Agent-tinted
                        // when on so users see WHICH agent the row is
                        // shared with at a glance.
                        //
                        // State + action are passed in explicitly: TableColumn
                        // cells on macOS don't reliably propagate @Observable
                        // environment values, so reading mailReview from inside
                        // the cell crashes during layout.
                        MailShareCheckbox(
                            isShared: mailReview.sharedEmailIDs.contains(row.emailID),
                            agent: mailReview.targetAgent,
                            emailID: row.emailID,
                            onToggle: {
                                let isShared = mailReview.sharedEmailIDs.contains(row.emailID)
                                Task { await mailReview.setMessageShared(row.emailID, isShared: !isShared) }
                            }
                        )
                    }
                    .width(min: 64, ideal: 72, max: 80)

                    TableColumn("Sender", value: \.senderSortKey) { row in
                        HStack(spacing: Spacing.s2) {
                            SenderAvatar(label: row.senderSortKey, size: 18)
                            Text(row.senderSortKey)
                                .font(ManifoldType.body)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selection = row.emailID
                                onOpenInspector()
                            }
                        )
                    }
                    .width(min: 160, ideal: 190)

                    TableColumn("Subject", value: \.subjectSortKey) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.subjectSortKey)
                                .font(ManifoldType.bodyMedium)
                                .lineLimit(1)
                            Text(row.previewText)
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selection = row.emailID
                                onOpenInspector()
                            }
                        )
                    }

                    TableColumn("Mailbox", value: \.mailboxSortKey) { row in
                        Text(row.mailboxSortKey)
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 140, max: 180)

                    TableColumn("Received", value: \.receivedDate) { row in
                        Text(MailDisplayFormatter.mailTimestamp(row.receivedAt))
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 120, max: 140)

                    TableColumn("Attach", value: \.attachmentCount) { row in
                        if row.attachmentCount > 0 {
                            Label("\(row.attachmentCount)", systemImage: "paperclip")
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 70, ideal: 80, max: 90)
                } rows: {
                    ForEach(rows) { row in
                        TableRow(row)
                            .contextMenu {
                                Button("Open inspector") {
                                    selection = row.emailID
                                    onOpenInspector()
                                }
                                Divider()
                                VisibilityActionMenu(row: row)
                            }
                    }
                }
                .tableStyle(.inset)
                .accessibilityIdentifier("mail.review.table")
            }
        }
    }

    private var syncBannerText: String? {
        guard let selectedAccount else { return nil }
        if !selectedAccount.syncEnabled {
            return "Backup is paused for this account. Sync again to refresh what’s visible here."
        }
        guard let lastSyncAt = selectedSyncState?.lastSyncAt else { return nil }
        let age = Date().timeIntervalSince(MailDisplayFormatter.date(from: lastSyncAt))
        return age > 86_400 ? "This mailbox backup is older than a day. Sync now if you need the latest messages." : nil
    }
}

private struct EmptyMailboxState: View {
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccount: EmailAccountRecord?
    let selectedSyncState: SyncStateRecord?

    var body: some View {
        ContentUnavailableView {
            Label("No backed-up messages in this mailbox", systemImage: "text.bubble")
        } description: {
            Text(descriptionText)
        } actions: {
            if selectedAccount != nil {
                Button("Sync now") {
                    Task { await mailReview.syncSelectedAccount() }
                }
            }
        }
    }

    private var descriptionText: String {
        guard let selectedAccount else {
            return "Choose an account and mailbox to browse backed-up mail."
        }
        if !selectedAccount.syncEnabled {
            return "Backup is paused for this account. Turn sync back on, then sync now to populate this mailbox."
        }
        if let lastSyncAt = selectedSyncState?.lastSyncAt {
            return "Manifold has a mailbox selected, but there are no backed-up messages here yet. Last backup \(MailDisplayFormatter.relativeTimestamp(lastSyncAt))."
        }
        return "Run a backup for this mailbox, then come back here to review and share individual messages."
    }
}

private struct ThreadInspector: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            if let selectedThread = mailReview.selectedThread,
               let selectedMessage = mailReview.selectedMessage {
                let visibilityState = mailReview.sharedEmailIDs.contains(selectedMessage.emailID)
                    ? VisibilityState(effective: .allowed, origin: .explicit)
                    : VisibilityState(effective: .hidden, origin: .defaultScope)
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HStack(alignment: .top, spacing: Spacing.s2) {
                        SenderAvatar(label: MailThreadRow.shortSender(from: selectedMessage.sender), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedMessage.subject.isEmpty ? "(No subject)" : selectedMessage.subject)
                                .font(ManifoldType.heading)
                            Text(MailThreadRow.shortSender(from: selectedMessage.sender))
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close message inspector")
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close inspector")
                        .accessibilityIdentifier("mail.inspector.close")
                    }

                    HStack(spacing: Spacing.s2) {
                        VisibilityChip(state: visibilityState)
                        Text(visibilityState.detail)
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("mail.message.inspector.visibility.\(selectedMessage.emailID)")

                    HStack(spacing: Spacing.s2) {
                        Button("Allow for \(AgentMeta.label(mailReview.targetAgent))") {
                            Task { await mailReview.setMessageShared(selectedMessage.emailID, isShared: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ManifoldPalette.selection)
                        .accessibilityIdentifier("mail.message.allow")

                        Button("Hide") {
                            Task { await mailReview.setMessageShared(selectedMessage.emailID, isShared: false) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("mail.message.hide")

                        Button("Reset") {
                            Task { await mailReview.setMessageShared(selectedMessage.emailID, isShared: false) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(visibilityState.origin != .explicit)
                        .accessibilityIdentifier("mail.message.reset")
                    }

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        inspectorRow("Received", MailDisplayFormatter.mailTimestamp(selectedMessage.receivedAt))
                        inspectorRow("Account", accountName(for: selectedMessage.accountID))
                        inspectorRow("Mailbox", selectedMessage.mailbox)
                        inspectorRow("Conversation", "\(selectedThread.messages.count) messages")
                        inspectorRow("Attachments", "\(selectedMessage.attachmentCount)")
                    }

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Safe excerpt")
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.4)

                        Text(MailDisplayFormatter.compactPreview(selectedMessage.preview ?? selectedMessage.bodyText ?? "No preview available"))
                            .font(ManifoldType.body)
                            .italic()
                            .padding(Spacing.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(ManifoldPalette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.6)
                            )
                    }

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Conversation context")
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.4)

                        ForEach(selectedThread.messageRows) { row in
                            HStack(spacing: Spacing.s2) {
                                Circle()
                                    .fill(mailReview.sharedEmailIDs.contains(row.emailID) ? ManifoldPalette.selection : ManifoldPalette.border2)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(MailThreadRow.shortSender(from: row.message.sender))
                                        .font(ManifoldType.captionMedium)
                                    Text(MailDisplayFormatter.mailTimestamp(row.message.receivedAt))
                                        .font(ManifoldType.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(Spacing.s4)
            } else {
                ContentUnavailableView(
                    "No message selected",
                    systemImage: "sidebar.right",
                    description: Text("Pick a backed-up message to inspect its metadata, safe excerpt, and visibility state.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            }
        }
    }

    private func accountName(for accountID: String) -> String {
        mailAccounts.accounts.first(where: { $0.accountID == accountID })?.displayName ?? accountID
    }

    @ViewBuilder
    private func inspectorRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(title)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(ManifoldType.caption)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct VisibilityActionMenu: View {
    @Environment(MailReviewModel.self) private var mailReview
    let row: MailReviewRow

    var body: some View {
        Button("Allow for \(AgentMeta.label(mailReview.targetAgent))") {
            Task { await mailReview.setMessageShared(row.emailID, isShared: true) }
        }
        Button("Hide") {
            Task { await mailReview.setMessageShared(row.emailID, isShared: false) }
        }
        Button("Reset to Default Hidden") {
            Task { await mailReview.setMessageShared(row.emailID, isShared: false) }
        }
        .disabled(row.visibilityState.origin != .explicit)
    }
}

private struct MailReviewRow: Identifiable, Hashable {
    let message: EmailMessageRecord
    let threadKey: String
    let visibilityState: VisibilityState

    var id: String { message.emailID }
    var emailID: String { message.emailID }
    var senderSortKey: String { MailThreadRow.shortSender(from: message.sender) }
    var subjectSortKey: String { message.subject.isEmpty ? "(No subject)" : message.subject }
    var mailboxSortKey: String { message.mailbox }
    var receivedDate: Date { MailDisplayFormatter.date(from: message.receivedAt) }
    var receivedAt: String { message.receivedAt }
    var attachmentCount: Int { message.attachmentCount }
    var previewText: String {
        MailDisplayFormatter.compactPreview(message.preview ?? message.bodyText ?? "No preview available")
    }
    var visibilitySortKey: String {
        "\(visibilityState.effective.rawValue)-\(visibilityState.origin.rawValue)"
    }
}

private struct SenderAvatar: View {
    let label: String
    var size: CGFloat = 22

    private var initials: String {
        let parts = label
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
        return parts.isEmpty ? "?" : parts
    }

    private var color: Color {
        let palette: [Color] = [
            ManifoldPalette.claude,
            ManifoldPalette.codex,
            ManifoldPalette.active,
            ManifoldPalette.attention,
            ManifoldPalette.paused,
        ]
        let hash = abs(label.lowercased().hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        Circle()
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}

enum MailDisplayFormatter {
    static func date(from rawValue: String) -> Date {
        ISO8601DateFormatter.shared.date(from: rawValue) ?? .distantPast
    }

    static func mailTimestamp(_ rawValue: String) -> String {
        let date = date(from: rawValue)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Today \(formatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    static func relativeTimestamp(_ rawValue: String?) -> String {
        guard let rawValue else { return "recently" }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date(from: rawValue), relativeTo: .now)
    }

    static func compactPreview(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Email share checkbox

/// Tappable checkbox cell for the Share column. Same visual language
/// as the redesigned files/folders matrix and the file inspector
/// selector — SF Symbol checkbox glyphs, agent-tinted when on.
///
/// State + action are passed explicitly rather than read from
/// @Environment. Tables on macOS don't reliably propagate @Observable
/// environment values into TableColumn cells; reading the model from
/// the cell crashes inside SwiftUI's EnvironmentBox.update during the
/// next layout pass (EXC_BREAKPOINT in EnvironmentValues.subscript).
/// Construct the closure where the environment is established (the
/// MailReviewTableArea body) and capture what's needed.
private struct MailShareCheckbox: View {
    let isShared: Bool
    let agent: TargetApp
    let emailID: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isShared ? "checkmark.square.fill" : "square")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isShared ? AgentMeta.color(agent) : Color.secondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isShared
              ? "Shared with \(AgentMeta.label(agent)). Click to hide."
              : "Hidden from \(AgentMeta.label(agent)). Click to share.")
        .accessibilityLabel(isShared ? "Shared, click to hide" : "Hidden, click to share")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("mail.share.\(emailID)")
    }
}
