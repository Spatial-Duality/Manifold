// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailReviewView — Active Backup-style mail review surface.
//
// This is intentionally not a mail client. The left rail scopes the
// backed-up mail, the center table is dense and sortable, and the
// inspector shows only the metadata and safe excerpt needed to make
// atomic allow / hide decisions.

import AppKit
import SwiftUI
import ManifoldKit

struct MailReviewView: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview
    @Environment(ManifoldStore.self) private var store
    @AppStorage("mail.review.pageSize") private var storedPageSize = 25
    @State private var sortOrder = [KeyPathComparator(\MailReviewRow.receivedDate, order: .reverse)]

    private var connectedAgents: [TargetApp] {
        AgentMeta.connected(from: store.connectedAgents)
    }

    private var connectedAgentsKey: String {
        AgentMeta.stableKey(connectedAgents)
    }
    @Binding var inspectorVisible: Bool

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

    private var selectedSyncProgress: MailSyncProgressSnapshot? {
        guard let accountID = mailReview.selectedAccountID else { return nil }
        return mailAccounts.progress(for: accountID)
    }

    private var selectedMailboxDisplayName: String? {
        guard let selectedAccount,
              let selectedMailboxName = mailReview.selectedMailboxName else {
            return mailReview.selectedMailboxName
        }
        return mailReview
            .sidebarMailboxes(for: selectedAccount)
            .first(where: { $0.mailboxName == selectedMailboxName })?
            .displayName ?? selectedMailboxName
    }

    private var reviewRows: [MailReviewRow] {
        mailReview.messages.map { message in
            let sharedAgents = mailReview.sharedAgents(for: message.emailID)
            let visibility: VisibilityState = sharedAgents.isEmpty
                ? VisibilityState(effective: .hidden, origin: .defaultScope)
                : VisibilityState(effective: .allowed, origin: .explicit)
            return MailReviewRow(
                message: message,
                threadKey: MailThreadRow.threadKey(for: message),
                visibilityState: visibility,
                sharedAgents: sharedAgents
            )
        }
    }

    private var sortOrderBinding: Binding<[KeyPathComparator<MailReviewRow>]> {
        Binding(
            get: { sortOrder },
            set: { newValue in
                sortOrder = newValue
                Task { await mailReview.resetPageAndReload() }
            }
        )
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
        VStack(spacing: 0) {
            ThreadToolbar(
                selectedAccount: selectedAccount,
                selectedMailboxName: mailReview.selectedMailboxName,
                selectedMailboxDisplayName: selectedMailboxDisplayName,
                selectedSyncProgress: selectedSyncProgress,
                isInspectorVisible: $inspectorVisible
            )
            Divider()
            MailReviewTableArea(
                selectedAccount: selectedAccount,
                selectedSyncState: selectedSyncState,
                selectedSyncProgress: selectedSyncProgress,
                rows: reviewRows,
                sortOrder: sortOrderBinding,
                selection: selectedMessageBinding,
                connectedAgents: connectedAgents,
                onOpenInspector: { inspectorVisible = true }
            )
        }
        .inspector(isPresented: $inspectorVisible) {
            ThreadInspector(connectedAgents: connectedAgents, onClose: { inspectorVisible = false })
                .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .task(id: connectedAgentsKey) {
            await mailReview.setConnectedAgents(connectedAgents)
        }
        .task(id: storedPageSize) {
            await mailReview.applyStoredPaging(pageSize: storedPageSize, pageIndex: 0)
        }
        .onChange(of: mailReview.pageSize) { _, newValue in
            if storedPageSize != newValue { storedPageSize = newValue }
        }
        .animation(ManifoldMotion.micro, value: inspectorVisible)
        .accessibilityElement(children: .contain)
    }
}

private struct ThreadToolbar: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccount: EmailAccountRecord?
    let selectedMailboxName: String?
    let selectedMailboxDisplayName: String?
    let selectedSyncProgress: MailSyncProgressSnapshot?
    @Binding var isInspectorVisible: Bool
    @State private var syncActivityPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s3) {
                Text(scopeStatusLine)
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    syncActivityPresented.toggle()
                } label: {
                    Label("Sync Activity", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $syncActivityPresented) {
                    MailSyncActivityPopover(
                        selectedAccountID: selectedAccount?.accountID,
                        snapshots: MailSyncProgressPresentation.orderedForActivity(
                            Array(mailAccounts.syncProgressByAccountID.values)
                        ),
                        eventsByAccountID: mailAccounts.syncActivityByAccountID
                    )
                    .frame(width: 360)
                }
                .help("Show mail sync activity")
                .accessibilityIdentifier("mail.syncActivity.button")

                Button("Sync now") {
                    Task { await mailReview.syncSelectedAccount() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                .accessibilityLabel(isInspectorVisible ? "Hide message inspector" : "Show message inspector")
                .accessibilityIdentifier("mail.inspector.toggle")
            }

            Text(summaryLine)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
    }

    private var scopeStatusLine: String {
        let trimmedSearch = mailReview.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            return "Search · All backed-up mail"
        }
        return MailSyncProgressPresentation.toolbarStatus(
            account: selectedAccount,
            mailboxDisplayName: selectedMailboxDisplayName,
            mailboxName: selectedMailboxName,
            progress: selectedSyncProgress
        )
    }

    private var summaryLine: String {
        let threadCount = mailReview.threadRows.count
        let pageStart = mailReview.totalMessageCount == 0 ? 0 : mailReview.pageOffset + 1
        let pageEnd = mailReview.pageOffset + mailReview.messages.count
        let pageSummary = "\(pageStart)-\(pageEnd) of \(mailReview.totalMessageCount)"
        let sharedCount = mailReview.sharedAnyAgentCount
        let agentCount = mailReview.connectedAgents.count
        let suffix: String
        switch agentCount {
        case 0: suffix = "shared"
        case 1: suffix = "shared with \(AgentMeta.label(mailReview.connectedAgents[0]))"
        default: suffix = "shared with at least one AI"
        }
        return "\(threadCount) conversations on page · \(pageSummary) messages · \(sharedCount) \(suffix)"
    }
}

private struct MailSyncActivityPopover: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccountID: String?
    let snapshots: [MailSyncProgressSnapshot]
    let eventsByAccountID: [String: [MailSyncActivityLogEntry]]

    private var visibleSnapshots: [MailSyncProgressSnapshot] {
        if let selectedAccountID,
           let selected = snapshots.first(where: { $0.accountID == selectedAccountID }) {
            return [selected]
        }
        return snapshots
    }

    var body: some View {
        Form {
            if visibleSnapshots.isEmpty {
                ContentUnavailableView(
                    "No sync activity",
                    systemImage: "envelope",
                    description: Text("Connect a mailbox to see local backup progress.")
                )
            } else {
                ForEach(visibleSnapshots) { snapshot in
                    accountSection(snapshot)
                    activitySection(snapshot)
                    mailboxSection(snapshot)
                }
            }
        }
        .formStyle(.grouped)
        .padding(Spacing.s2)
        .accessibilityIdentifier("mail.syncActivity.popover")
    }

    private func accountSection(_ snapshot: MailSyncProgressSnapshot) -> some View {
        Section(snapshot.displayName) {
            LabeledContent("Status") {
                MailSyncStatusLabel(stage: snapshot.stage)
            }
            LabeledContent("Synced messages") {
                Text(MailSyncProgressPresentation.formattedCount(snapshot.syncedMessageCount))
                    .monospacedDigit()
            }
            LabeledContent("Running jobs", value: "\(snapshot.runningJobCount)")
            LabeledContent("Queued backfills", value: "\(snapshot.queuedBackfillCount)")
            LabeledContent("Queued retries", value: "\(snapshot.retryScheduledCount)")
            LabeledContent("Current work") {
                Text(currentWorkText(snapshot))
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Last updated", value: lastUpdatedText(snapshot))
            if let completed = snapshot.progressCompleted,
               let total = snapshot.progressTotal,
               total > 0 {
                ProgressView(value: Double(completed), total: Double(total))
            } else if snapshot.stage.isActive {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Sync Now", systemImage: "arrow.clockwise") {
                Task {
                    if selectedAccountID == snapshot.accountID {
                        await mailReview.syncSelectedAccount()
                    } else {
                        await mailAccounts.syncNow(accountID: snapshot.accountID)
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private func activitySection(_ snapshot: MailSyncProgressSnapshot) -> some View {
        Section("Recent Activity") {
            let events = eventsByAccountID[snapshot.accountID] ?? []
            if events.isEmpty {
                Text("No sync activity has been recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(8)) { event in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(MailSyncProgressPresentation.eventTitle(event))
                            if let detail = event.detailRedacted, !detail.isEmpty {
                                Text(detail)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    } label: {
                        Text(MailSyncProgressPresentation.relativeTimestamp(event.createdAt) ?? "recently")
                    }
                }
            }
        }
    }

    private func mailboxSection(_ snapshot: MailSyncProgressSnapshot) -> some View {
        Section {
            DisclosureGroup("Mailboxes") {
                if snapshot.mailboxSyncedCounts.isEmpty {
                    Text("No synced mailbox counts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.mailboxSyncedCounts.keys.sorted(), id: \.self) { mailboxName in
                        LabeledContent(mailboxName) {
                            Text(MailSyncProgressPresentation.formattedCount(
                                snapshot.mailboxSyncedCounts[mailboxName] ?? 0
                            ))
                            .monospacedDigit()
                        }
                    }
                }
            }

            if !snapshot.failedMailboxNames.isEmpty {
                DisclosureGroup("Mailbox Errors") {
                    ForEach(snapshot.failedMailboxNames, id: \.self) { mailboxName in
                        Text(mailboxName)
                    }
                    if let errorMessage = snapshot.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func currentWorkText(_ snapshot: MailSyncProgressSnapshot) -> String {
        var parts = [MailSyncProgressPresentation.runningJobTitle(snapshot.currentJobType)]
        if let mailbox = snapshot.currentMailboxName, !mailbox.isEmpty {
            parts.append(mailbox)
        }
        return parts.joined(separator: " · ")
    }

    private func lastUpdatedText(_ snapshot: MailSyncProgressSnapshot) -> String {
        MailSyncProgressPresentation.relativeTimestamp(snapshot.lastUpdatedAt) ?? "Not yet"
    }
}

private struct MailReviewTableArea: View {
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccount: EmailAccountRecord?
    let selectedSyncState: SyncStateRecord?
    let selectedSyncProgress: MailSyncProgressSnapshot?
    let rows: [MailReviewRow]
    @Binding var sortOrder: [KeyPathComparator<MailReviewRow>]
    @Binding var selection: String?
    let connectedAgents: [TargetApp]
    let onOpenInspector: () -> Void

    private var shareColumnWidth: CGFloat {
        AccessCheckboxStrip.compactWidth(agentCount: connectedAgents.count)
    }

    private var tableIdentity: String {
        [
            mailReview.selectedAccountID ?? "none",
            mailReview.selectedMailboxName ?? "none",
            mailReview.activeQuickFilter?.rawValue ?? "all",
            mailReview.searchText,
            "\(mailReview.pageSize)",
            "\(mailReview.pageIndex)",
            rows.map(\.emailID).joined(separator: ","),
        ].joined(separator: "::")
    }

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
            EmptyMailboxState(
                selectedAccount: selectedAccount,
                selectedSyncState: selectedSyncState,
                selectedSyncProgress: selectedSyncProgress
            )
        } else {
            VStack(spacing: 0) {
                if let banner = syncBannerText {
                    HStack(spacing: Spacing.s2) {
                        Label(banner, systemImage: "clock.arrow.circlepath")
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s2)
                }

                Table(of: MailReviewRow.self, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Share", value: \.sharedAgentCount) { row in
                        // sharedAgents is captured on the row at build time;
                        // reading mailReview from inside a TableColumn cell
                        // crashes layout (@Observable env doesn't propagate
                        // reliably into Table cells on macOS).
                        AccessCheckboxStrip(
                            agents: connectedAgents,
                            visibleAgents: row.sharedAgents,
                            showsTitles: false,
                            accessibilityIDPrefix: "mail.share.\(row.emailID)",
                            onToggleAgent: { agent, wasVisible in
                                Task {
                                    await mailReview.setMessageShared(
                                        row.emailID,
                                        agent: agent,
                                        isShared: !wasVisible
                                    )
                                }
                            },
                            onSetAll: { isShared in
                                Task {
                                    await mailReview.setMessageSharedForAllAgents(
                                        row.emailID,
                                        isShared: isShared
                                    )
                                }
                            }
                        )
                        .accessibilityIdentifier("mail.share.\(row.emailID)")
                    }
                    .width(min: shareColumnWidth, ideal: shareColumnWidth, max: shareColumnWidth)

                    TableColumn("Sender", value: \.senderSortKey) { row in
                        HStack(spacing: Spacing.s2) {
                            SenderAvatar(label: row.senderSortKey, size: 18)
                            Text(row.senderSortKey)
                                .font(ManifoldType.body)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = row.emailID
                            onOpenInspector()
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selection = row.emailID
                                onOpenInspector()
                            }
                        )
                        // The tap gesture is invisible to VoiceOver;
                        // expose the same behavior as the default action.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            selection = row.emailID
                            onOpenInspector()
                        }
                    }
                    .width(min: 110, ideal: 150, max: 200)

                    // No max width — Subject takes any flex left over.
                    TableColumn("Subject", value: \.subjectSortKey) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.subjectSortKey)
                                .font(ManifoldType.bodyMedium)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(row.previewText)
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("mail.message.row.\(row.emailID)")
                        .onTapGesture {
                            selection = row.emailID
                            onOpenInspector()
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selection = row.emailID
                                onOpenInspector()
                            }
                        )
                        // The tap gesture is invisible to VoiceOver;
                        // expose the same behavior as the default action.
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            selection = row.emailID
                            onOpenInspector()
                        }
                    }
                    .width(min: 240, ideal: 420)

                    TableColumn("Mailbox", value: \.mailboxSortKey) { row in
                        Text(row.mailboxSortKey)
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .width(min: 90, ideal: 110, max: 150)

                    TableColumn("Received", value: \.receivedDate) { row in
                        Text(MailDisplayFormatter.mailTimestamp(row.receivedAt, isTrusted: row.receivedAtIsTrusted))
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 92, ideal: 110, max: 130)

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
                    .width(min: 56, ideal: 64, max: 76)
                } rows: {
                    ForEach(rows) { row in
                        TableRow(row)
                            .contextMenu {
                                Button("Open inspector") {
                                    selection = row.emailID
                                    onOpenInspector()
                                }
                                Divider()
                                VisibilityActionMenu(row: row, connectedAgents: connectedAgents)
                            }
                    }
                }
                .tableStyle(.inset)
                .id(tableIdentity)
                .accessibilityIdentifier("mail.review.table")

                Divider()
                MailPagerBar()
            }
        }
    }

    private var syncBannerText: String? {
        guard let selectedAccount else { return nil }
        if !selectedAccount.syncEnabled {
            return "Backup is paused for this account. Sync again to refresh what’s visible here."
        }
        if let selectedSyncProgress {
            switch selectedSyncProgress.stage {
            case .syncingRecentMail:
                return "Recent mail is syncing. You can leave this window open; older mail will archive in the background."
            case .recentMailReady:
                return "Recent mail is ready. Manifold is archiving older messages in the background."
            case .archivingOlderMail:
                return "Manifold is archiving older messages. Recent mail remains available."
            case .checkingMailboxes:
                return "Manifold is checking mailboxes before backing up recent mail."
            case .indexingPrivately:
                return "Manifold is indexing backed-up mail locally for private review."
            case .needsAttention:
                return "Mail sync needs attention. Open Sync Activity for details."
            case .paused, .upToDate:
                break
            }
        }
        guard let lastSyncAt = selectedSyncState?.lastSyncAt else { return nil }
        let age = Date().timeIntervalSince(MailDisplayFormatter.date(from: lastSyncAt))
        return age > 86_400 ? "This mailbox backup is older than a day. Sync now if you need the latest messages." : nil
    }
}

private struct MailPagerBar: View {
    @Environment(MailReviewModel.self) private var mailReview

    private let pageSizes = [25, 50, 75]

    var body: some View {
        HStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                Text("Rows")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Picker("Rows", selection: pageSizeBinding) {
                    ForEach(pageSizes, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 108)
                .accessibilityIdentifier("mail.pager.pageSize")
            }
            .fixedSize(horizontal: true, vertical: false)

            Text(rangeText)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await mailReview.previousPage() }
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!mailReview.canPageBackward)
            .help("Previous page")
            .accessibilityIdentifier("mail.pager.previous")

            Button {
                Task { await mailReview.nextPage() }
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!mailReview.canPageForward)
            .help("Next page")
            .accessibilityIdentifier("mail.pager.next")
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
    }

    private var pageSizeBinding: Binding<Int> {
        Binding(
            get: { mailReview.pageSize },
            set: { newValue in
                Task { await mailReview.setPageSize(newValue) }
            }
        )
    }

    private var rangeText: String {
        guard mailReview.totalMessageCount > 0 else { return "0 of 0" }
        let start = mailReview.pageOffset + 1
        let end = min(mailReview.pageOffset + mailReview.messages.count, mailReview.totalMessageCount)
        return "\(start)-\(end) of \(mailReview.totalMessageCount)"
    }
}

private struct EmptyMailboxState: View {
    @Environment(MailReviewModel.self) private var mailReview

    let selectedAccount: EmailAccountRecord?
    let selectedSyncState: SyncStateRecord?
    let selectedSyncProgress: MailSyncProgressSnapshot?

    var body: some View {
        ContentUnavailableView {
            Label(titleText, systemImage: systemImage)
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

    private var titleText: String {
        if !mailReview.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching backed-up mail"
        }
        guard selectedAccount != nil else { return "No mailbox selected" }
        if selectedSyncProgress?.stage == .needsAttention || selectedSyncState?.syncStatus == .error {
            return "Mailbox needs attention"
        }
        if selectedAccount?.syncEnabled == false || selectedSyncProgress?.stage == .paused {
            return "Mail backup is paused"
        }
        if selectedSyncProgress?.stage == .checkingMailboxes
            || selectedSyncProgress?.stage == .syncingRecentMail {
            return "Mailbox is syncing"
        }
        return "No backed-up messages in this mailbox"
    }

    private var systemImage: String {
        guard selectedAccount != nil else { return "tray" }
        if selectedSyncProgress?.stage == .needsAttention || selectedSyncState?.syncStatus == .error {
            return "exclamationmark.triangle"
        }
        if selectedAccount?.syncEnabled == false || selectedSyncProgress?.stage == .paused {
            return "pause.circle"
        }
        if selectedSyncProgress?.stage == .checkingMailboxes
            || selectedSyncProgress?.stage == .syncingRecentMail {
            return "arrow.triangle.2.circlepath"
        }
        return "text.bubble"
    }

    private var descriptionText: String {
        if !mailReview.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search checks all backed-up mail, not just the selected mailbox or filter."
        }
        guard let selectedAccount else {
            return "Choose an account and mailbox to browse backed-up mail."
        }
        if !selectedAccount.syncEnabled {
            return "Backup is paused for this account. Turn sync back on, then sync now to populate this mailbox."
        }
        if selectedSyncProgress?.stage == .needsAttention || selectedSyncState?.syncStatus == .error {
            return selectedSyncProgress?.errorMessage
                ?? selectedSyncState?.errorMessage
                ?? "Manifold could not finish backing up this mailbox. Open Sync Activity or sync again."
        }
        if selectedSyncProgress?.stage == .checkingMailboxes {
            return "Manifold is checking available mailboxes. Messages will appear here after recent mail starts syncing."
        }
        if selectedSyncProgress?.stage == .syncingRecentMail {
            return "Recent mail is syncing. You can keep working while Manifold backs up this mailbox locally."
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Magic moment trigger (R3.1): increments on every distinct
    /// message-open so the inspector body breathes in with a brief
    /// scale + opacity pulse. Honors reduce-motion automatically:
    /// keyframeAnimator is skipped entirely when disabled.
    @State private var openMomentToken: Int = 0
    @State private var attachments: [EmailAttachmentRecord] = []
    @State private var sharedAttachmentIDsByAgent: [TargetApp: Set<String>] = [:]
    @State private var attachmentError: String?
    let connectedAgents: [TargetApp]
    let onClose: () -> Void

    private var connectedAgentsKey: String {
        AgentMeta.stableKey(connectedAgents)
    }

    var body: some View {
        ScrollView {
            if let selectedThread = mailReview.selectedThread,
               let selectedMessage = mailReview.selectedMessage {
                let sharedAgents = mailReview.sharedAgents(for: selectedMessage.emailID)
                let visibilityState: VisibilityState = sharedAgents.isEmpty
                    ? VisibilityState(effective: .hidden, origin: .defaultScope)
                    : VisibilityState(effective: .allowed, origin: .explicit)
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

                    AccessCheckboxStrip(
                        agents: connectedAgents,
                        visibleAgents: sharedAgents,
                        accessibilityIDPrefix: "mail.message.share",
                        onToggleAgent: { agent, wasVisible in
                            Task {
                                await mailReview.setMessageShared(
                                    selectedMessage.emailID,
                                    agent: agent,
                                    isShared: !wasVisible
                                )
                            }
                        },
                        onSetAll: { newValue in
                            Task {
                                await mailReview.setMessageSharedForAllAgents(
                                    selectedMessage.emailID,
                                    isShared: newValue
                                )
                            }
                        }
                    )

                    Button {
                        openEmail(selectedMessage.emailID)
                    } label: {
                        Label("Open Email", systemImage: "envelope.open")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("mail.inspector.openEmail.\(selectedMessage.emailID)")

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        inspectorRow("Received", MailDisplayFormatter.mailTimestamp(selectedMessage.receivedAt))
                        inspectorRow("Account", accountName(for: selectedMessage.accountID))
                        inspectorRow("Mailbox", selectedMessage.mailbox)
                        inspectorRow("Conversation", "\(selectedThread.messages.count) messages")
                        inspectorRow("Attachments", "\(selectedMessage.attachmentCount)")
                    }

                    if selectedMessage.attachmentCount > 0 || !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Text("Attachments")
                                .font(ManifoldType.tiny)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .tracking(0.4)

                            if let attachmentError {
                                Text(attachmentError)
                                    .font(ManifoldType.caption)
                                    .foregroundStyle(ManifoldPalette.danger)
                            } else if attachments.isEmpty {
                                Text("No attachment metadata found.")
                                    .font(ManifoldType.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(attachments) { attachment in
                                    AttachmentInspectorRow(
                                        attachment: attachment,
                                        connectedAgents: connectedAgents,
                                        visibleAgents: visibleAttachmentAgents(for: attachment),
                                        onToggleAgent: { agent, wasVisible in
                                            Task {
                                                await setAttachmentShared(
                                                    attachment.attachmentID,
                                                    agent: agent,
                                                    isShared: !wasVisible,
                                                    emailID: selectedMessage.emailID
                                                )
                                            }
                                        },
                                        onSetAll: { isShared in
                                            Task {
                                                await setAttachmentSharedForAllAgents(
                                                    attachment.attachmentID,
                                                    isShared: isShared,
                                                    emailID: selectedMessage.emailID
                                                )
                                            }
                                        },
                                        onOpen: {
                                            openAttachment(attachment.attachmentID, reveal: false)
                                        },
                                        onReveal: {
                                            openAttachment(attachment.attachmentID, reveal: true)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        HStack {
                            Text("Message")
                                .font(ManifoldType.tiny)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .tracking(0.4)
                            Spacer()
                        }

                        let messageBody = (selectedMessage.bodyText?.isEmpty == false
                            ? selectedMessage.bodyText
                            : selectedMessage.preview)?.trimmingCharacters(in: .whitespacesAndNewlines)

                        ScrollView {
                            Text(messageBody?.isEmpty == false
                                 ? messageBody!
                                 : "No message body extracted yet.")
                                .font(ManifoldType.body)
                                .foregroundStyle(messageBody?.isEmpty == false ? .primary : .secondary)
                                .textSelection(.enabled)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.s3)
                        }
                        .frame(minHeight: 220, maxHeight: 360)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ManifoldPalette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ManifoldPalette.border, lineWidth: 0.6)
                        )
                        .accessibilityIdentifier("mail.message.body.\(selectedMessage.emailID)")
                    }

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Conversation context")
                            .font(ManifoldType.tiny)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .tracking(0.4)

                        ForEach(selectedThread.messageRows) { row in
                            HStack(spacing: Spacing.s2) {
                                Circle()
                                    .fill(mailReview.sharedAgents(for: row.emailID).isEmpty ? ManifoldPalette.border2 : ManifoldPalette.selection)
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
                // R3.1 magic moment: brief breathe-in on every distinct
                // message-open. Reduce-motion skips the animation
                // entirely (the content appears immediately).
                .modifier(MailBodyOpenMoment(trigger: openMomentToken,
                                              reduceMotion: reduceMotion))
            } else {
                ContentUnavailableView(
                    "No message selected",
                    systemImage: "sidebar.right",
                    description: Text("Pick a backed-up message to inspect its metadata, redacted preview, and visibility state.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            }
        }
        .onChange(of: mailReview.selectedMessageID) { _, newID in
            if newID != nil { openMomentToken &+= 1 }
        }
        .task(id: "\(mailReview.selectedMessageID ?? "none")-\(connectedAgentsKey)") {
            await loadAttachmentsForSelectedMessage()
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

    private func visibleAttachmentAgents(for attachment: EmailAttachmentRecord) -> Set<TargetApp> {
        Set(connectedAgents.filter { agent in
            sharedAttachmentIDsByAgent[agent, default: []].contains(attachment.attachmentID)
        })
    }

    private func loadAttachmentsForSelectedMessage() async {
        guard let message = mailReview.selectedMessage else {
            attachments = []
            sharedAttachmentIDsByAgent = [:]
            attachmentError = nil
            return
        }

        let loaded = await mailAccounts.attachments(emailID: message.emailID)
        var nextShared: [TargetApp: Set<String>] = [:]
        for agent in connectedAgents {
            nextShared[agent] = await mailAccounts.sharedEmailAttachmentIDs(agent: agent, emailID: message.emailID)
        }
        attachments = loaded
        sharedAttachmentIDsByAgent = nextShared
        attachmentError = mailAccounts.lastQueryError
    }

    private func setAttachmentShared(
        _ attachmentID: String,
        agent: TargetApp,
        isShared: Bool,
        emailID: String
    ) async {
        if isShared {
            await mailAccounts.shareEmailAttachments(attachmentIDs: [attachmentID], for: agent)
        } else {
            await mailAccounts.unshareEmailAttachments(attachmentIDs: [attachmentID], for: agent)
        }
        sharedAttachmentIDsByAgent[agent] = await mailAccounts.sharedEmailAttachmentIDs(agent: agent, emailID: emailID)
        attachmentError = mailAccounts.lastQueryError
    }

    private func setAttachmentSharedForAllAgents(
        _ attachmentID: String,
        isShared: Bool,
        emailID: String
    ) async {
        for agent in connectedAgents {
            await setAttachmentShared(attachmentID, agent: agent, isShared: isShared, emailID: emailID)
        }
    }

    private func openEmail(_ emailID: String) {
        Task {
            guard let path = await mailAccounts.openEmail(emailID: emailID) else {
                attachmentError = mailAccounts.lastQueryError
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func openAttachment(_ attachmentID: String, reveal: Bool) {
        Task {
            guard let path = await mailAccounts.openAttachment(attachmentID: attachmentID) else {
                attachmentError = mailAccounts.lastQueryError
                return
            }
            let url = URL(fileURLWithPath: path)
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct AttachmentInspectorRow: View {
    let attachment: EmailAttachmentRecord
    let connectedAgents: [TargetApp]
    let visibleAgents: Set<TargetApp>
    let onToggleAgent: (TargetApp, Bool) -> Void
    let onSetAll: (Bool) -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(ManifoldType.captionMedium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(attachment.mimeType) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))")
                        .font(ManifoldType.tiny)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    onOpen()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open attachment")
                .accessibilityLabel("Open attachment")

                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Reveal attachment")
                .accessibilityLabel("Reveal attachment")
            }

            AccessCheckboxStrip(
                agents: connectedAgents,
                visibleAgents: visibleAgents,
                accessibilityIDPrefix: "mail.attachment.share.\(attachment.attachmentID)",
                onToggleAgent: onToggleAgent,
                onSetAll: onSetAll
            )
        }
        .padding(Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.6)
        )
    }
}

private struct VisibilityActionMenu: View {
    @Environment(MailReviewModel.self) private var mailReview
    let row: MailReviewRow
    let connectedAgents: [TargetApp]

    var body: some View {
        if !connectedAgents.isEmpty {
            Button("Share with all") {
                Task { await mailReview.setMessageSharedForAllAgents(row.emailID, isShared: true) }
            }
            Button("Hide from all") {
                Task { await mailReview.setMessageSharedForAllAgents(row.emailID, isShared: false) }
            }
            Divider()
            ForEach(connectedAgents, id: \.self) { agent in
                let isShared = mailReview.isShared(row.emailID, agent: agent)
                Button(isShared
                       ? "Hide from \(AgentMeta.label(agent))"
                       : "Share with \(AgentMeta.label(agent))") {
                    Task {
                        await mailReview.setMessageShared(
                            row.emailID,
                            agent: agent,
                            isShared: !isShared
                        )
                    }
                }
            }
        }
    }
}

private struct MailReviewRow: Identifiable, Hashable {
    let message: EmailMessageRecord
    let threadKey: String
    let visibilityState: VisibilityState
    /// AIs that can see this message, captured once when the row is
    /// built. Cells render directly from this set instead of re-asking
    /// the model — avoids N×M lookups per table render.
    let sharedAgents: Set<TargetApp>

    var sharedAgentCount: Int { sharedAgents.count }
    var id: String { message.emailID }
    var emailID: String { message.emailID }
    var senderSortKey: String { MailThreadRow.shortSender(from: message.sender) }
    var subjectSortKey: String { message.subject.isEmpty ? "(No subject)" : message.subject }
    var mailboxSortKey: String { message.mailbox }
    var receivedDate: Date { MailDisplayFormatter.date(from: message.receivedAt) }
    var receivedAt: String { message.receivedAt }
    var receivedAtIsTrusted: Bool { message.receivedAtIsTrusted }
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
    private static let todayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    nonisolated(unsafe) private static let relativeFormatter = RelativeDateTimeFormatter()

    static func date(from rawValue: String) -> Date {
        MailDateNormalizer.parse(rawValue) ?? .distantPast
    }

    static func mailTimestamp(_ rawValue: String, isTrusted: Bool = true) -> String {
        guard isTrusted, MailDateNormalizer.parse(rawValue) != nil else {
            return "Unknown"
        }
        let date = date(from: rawValue)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today \(todayTimeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return monthDayFormatter.string(from: date)
    }

    static func relativeTimestamp(_ rawValue: String?) -> String {
        guard let rawValue else { return "recently" }
        return relativeFormatter.localizedString(for: date(from: rawValue), relativeTo: .now)
    }

    static func compactPreview(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - R3.1 magic moment: mail body open

/// Brief scale + opacity pulse fired when a new message is selected.
/// One of three R3 magic moments per primary surface (Mail / Files /
/// Approvals) that bring the working surface to ADA-grade interaction
/// polish. Reduce-motion aware — the animator is skipped entirely
/// when the user has accessibility motion disabled.
private struct MailBodyOpenMoment: ViewModifier {
    let trigger: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(
                initialValue: BodyOpenState(scale: 1, opacity: 1),
                trigger: trigger
            ) { view, value in
                view
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(0.985, duration: 0.0)
                    SpringKeyframe(1.000, duration: 0.30, spring: .smooth)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.6, duration: 0.0)
                    LinearKeyframe(1.0, duration: 0.22)
                }
            }
        }
    }
}

private struct BodyOpenState: Animatable {
    var scale: CGFloat
    var opacity: Double
    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(scale, opacity) }
        set {
            scale = newValue.first
            opacity = newValue.second
        }
    }
}
