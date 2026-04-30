// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailboxesMatrixView — mailbox overview with a handoff into the live
// browser. This stays operator-first: account + mailbox selection on the
// left, a compact inspector on the right, and no reading pane.

import SwiftUI
import ManifoldKit

struct MailboxesMatrixView: View {
    @Environment(MailAccountsModel.self) private var mailAccounts
    @Environment(MailReviewModel.self) private var mailReview

    let onBrowseMessages: () -> Void

    private var selectedAccount: EmailAccountRecord? {
        guard let accountID = mailReview.selectedAccountID else { return nil }
        return mailAccounts.accounts.first(where: { $0.accountID == accountID })
    }

    private var selectedMailbox: IMAPMailboxRecord? {
        guard let accountID = mailReview.selectedAccountID,
              let mailboxName = mailReview.selectedMailboxName else {
            return nil
        }
        return mailReview.mailboxes(for: accountID).first(where: { $0.mailboxName == mailboxName })
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s5) {
                    ForEach(mailAccounts.accounts) { account in
                        MailboxAccountSection(
                            account: account,
                            mailboxes: mailReview.mailboxes(for: account.accountID),
                            selectedMailboxName: account.accountID == mailReview.selectedAccountID
                                ? mailReview.selectedMailboxName
                                : nil
                        ) { mailbox in
                            Task {
                                await mailReview.browse(
                                    accountID: account.accountID,
                                    mailbox: mailbox.mailboxName
                                )
                            }
                        }
                    }
                }
                .padding(Spacing.s4)
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity)

            Divider()

            MailboxInspector(
                account: selectedAccount,
                mailbox: selectedMailbox,
                syncStates: selectedAccount.map { mailAccounts.syncStates[$0.accountID] ?? [] } ?? [],
                onBrowseMessages: onBrowseMessages
            )
            .frame(width: 320)
            .background(ManifoldPalette.surface2)
        }
    }
}

private struct MailboxAccountSection: View {
    let account: EmailAccountRecord
    let mailboxes: [IMAPMailboxRecord]
    let selectedMailboxName: String?
    let onSelect: (IMAPMailboxRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .center, spacing: Spacing.s2) {
                Image(systemName: account.provider.systemImage)
                    .foregroundStyle(ManifoldPalette.codex)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(ManifoldType.bodyMedium)
                    Text(account.username ?? account.provider.displayName)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if account.syncEnabled {
                    Pill(text: "backed up", variant: .session)
                } else {
                    Pill(text: "sync paused", variant: .attention)
                }
            }

            if mailboxes.isEmpty {
                ContentUnavailableView(
                    "No synced mailboxes yet",
                    systemImage: "tray",
                    description: Text("Run a backup for this account to browse individual messages through Manifold.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s4)
            } else {
                VStack(spacing: Spacing.s2) {
                    ForEach(mailboxes) { mailbox in
                        MailboxRow(
                            account: account,
                            mailbox: mailbox,
                            isSelected: selectedMailboxName == mailbox.mailboxName,
                            onSelect: { onSelect(mailbox) }
                        )
                    }
                }
            }
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ManifoldPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ManifoldPalette.border, lineWidth: 0.6)
        )
    }
}

private struct MailboxRow: View {
    let account: EmailAccountRecord
    let mailbox: IMAPMailboxRecord
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s3) {
                Image(systemName: mailbox.folderType.systemImage)
                    .foregroundStyle(isSelected ? ManifoldPalette.selection : ManifoldPalette.text2)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mailbox.mailboxName)
                        .font(ManifoldType.body)
                    Text(account.displayName)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if mailbox.folderType == .inbox {
                    Pill(text: "inbox", variant: .defaultScope)
                } else {
                    Pill(text: mailbox.folderType.rawValue, variant: .neutral)
                }
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? ManifoldPalette.selectionSoft : ManifoldPalette.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? ManifoldPalette.selection.opacity(0.35) : ManifoldPalette.border,
                        lineWidth: 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mail.mailbox.\(account.accountID).\(mailbox.mailboxName)")
    }
}

/// The 3-option sensitivity selector shown in the mailbox inspector.
struct SensitivitySelector: View {
    enum Level: String, Hashable, CaseIterable {
        case subjects, trusted, full

        var label: String {
            switch self {
            case .subjects: return "Subjects only"
            case .trusted:  return "Trusted senders"
            case .full:     return "Full content"
            }
        }
    }

    @Binding var level: Level

    var body: some View {
        SegmentedToggle(
            selection: $level,
            options: Level.allCases.map { lvl in
                SegmentedToggle<Level>.Option(
                    value: lvl,
                    label: lvl.label,
                    tint: tint(for: lvl)
                )
            }
        )
    }

    private func tint(for level: Level) -> Color {
        switch level {
        case .subjects: return ManifoldPalette.claude
        case .trusted:  return ManifoldPalette.active
        case .full:     return ManifoldPalette.attention
        }
    }
}

struct MailboxInspector: View {
    let account: EmailAccountRecord?
    let mailbox: IMAPMailboxRecord?
    let syncStates: [SyncStateRecord]
    let onBrowseMessages: () -> Void

    @State private var level: SensitivitySelector.Level = .trusted

    private var syncState: SyncStateRecord? {
        guard let mailbox else { return nil }
        return syncStates.first(where: { $0.mailboxName == mailbox.mailboxName })
    }

    var body: some View {
        ScrollView {
            if let account, let mailbox {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: mailbox.folderType.systemImage)
                            .foregroundStyle(ManifoldPalette.claude)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mailbox.mailboxName)
                                .font(ManifoldType.heading)
                            Text(account.displayName)
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let syncState {
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Pill(text: syncState.syncStatus.rawValue.replacingOccurrences(of: "_", with: " "), variant: syncVariant(syncState.syncStatus))
                            Text(syncCopy(for: syncState))
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text("Sharing mode")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    SensitivitySelector(level: $level)
                    Text("Use this as the mailbox default when deciding which messages to share in a Manifold session.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Through Manifold")
                            .font(ManifoldType.tiny.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        Text(copy(for: level))
                            .font(ManifoldType.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Browse messages", action: onBrowseMessages)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("mail.browseMessages")
                }
                .padding(Spacing.s4)
            } else {
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "tray.2")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a mailbox to browse backed-up mail through Manifold.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.s8)
            }
        }
    }

    private func copy(for level: SensitivitySelector.Level) -> String {
        switch level {
        case .subjects:
            return "Subjects and sender addresses are visible through Manifold. Message bodies stay hidden."
        case .trusted:
            return "Trusted-sender bodies are visible through Manifold while the rest stay metadata-only."
        case .full:
            return "Bodies and attachments are visible through Manifold. Use this only for low-sensitivity mail."
        }
    }

    private func syncVariant(_ status: SyncStatus) -> Pill.Variant {
        switch status {
        case .idle: return .session
        case .syncing: return .defaultScope
        case .error, .pausedNoDrive: return .attention
        }
    }

    private func syncCopy(for state: SyncStateRecord) -> String {
        var segments: [String] = []
        if let lastSyncAt = state.lastSyncAt {
            segments.append("Last backup \(MailDisplayFormatter.relativeTimestamp(lastSyncAt)).")
        }
        segments.append("\(state.messageCount) messages indexed in this mailbox.")
        if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
            segments.append(errorMessage)
        }
        return segments.joined(separator: " ")
    }
}
