// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct MailSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @Binding var addAccountSheetPresented: Bool
    @State private var accountPendingDeletion: EmailAccountRecord?
    @State private var deletingAccountID: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Accounts") {
                    if store.mailAccounts.accounts.isEmpty {
                        ContentUnavailableView(
                            "No mailboxes connected",
                            systemImage: "envelope.badge",
                            description: Text("Connect a mailbox so Claude or Codex can see subject lines — or trusted-sender bodies — during a session.")
                        )
                        .padding(.vertical, Spacing.s4)
                    } else {
                        ForEach(store.mailAccounts.accounts) { account in
                            MailAccountRow(
                                account: account,
                                progress: store.mailAccounts.progress(for: account),
                                syncEnabled: syncBinding(for: account),
                                isDeleting: deletingAccountID == account.accountID,
                                onSyncNow: {
                                    Task { await store.mailAccounts.syncNow(accountID: account.accountID) }
                                },
                                onDelete: {
                                    accountPendingDeletion = account
                                }
                            )
                        }
                    }

                    Button("Connect a mailbox\u{2026}", systemImage: "plus") {
                        addAccountSheetPresented = true
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("settings.mail.connectAccount")
                }

                Section("Storage") {
                    LabeledContent("Archive location") {
                        PathLabel(store.mailAccounts.archiveRootPath)
                    }
                    LabeledContent("Total messages") {
                        Text("\(store.mailAccounts.totalMessageCount)")
                            .monospacedDigit()
                    }
                    if let historyPath = store.mailAccounts.lastRemovalHistoryPath {
                        LabeledContent("Last removal history") {
                            PathLabel(historyPath)
                        }
                    }
                    if let error = store.mailAccounts.lastRemovalError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Delete this mail account and local data?",
            isPresented: deletionConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let account = accountPendingDeletion {
                Button("Delete Account and Local Mail Data", role: .destructive) {
                    deletingAccountID = account.accountID
                    Task {
                        _ = await store.mailAccounts.removeAccount(id: account.accountID)
                        deletingAccountID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let account = accountPendingDeletion {
                Text("Manifold will remove \(account.displayName), all locally stored mail, encrypted archive blobs, search indexes, sync state, and Keychain credentials. Agent access context is saved first as a plain text file.")
            }
        }
    }

    private var deletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { accountPendingDeletion != nil },
            set: { presented in
                if !presented {
                    accountPendingDeletion = nil
                }
            }
        )
    }

    /// Stable sync-state binding per account. Replaces the prior inline
    /// Binding(get:set:) per references/data.md.
    private func syncBinding(for account: EmailAccountRecord) -> Binding<Bool> {
        Binding(
            get: { account.syncEnabled },
            set: { enabled in
                Task {
                    await store.mailAccounts.toggleSync(
                        accountID: account.accountID,
                        enabled: enabled
                    )
                }
            }
        )
    }
}

// MARK: - Mail account row

private struct MailAccountRow: View {
    let account: EmailAccountRecord
    let progress: MailSyncProgressSnapshot?
    @Binding var syncEnabled: Bool
    let isDeleting: Bool
    let onSyncNow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s3) {
                providerGlyph
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(ManifoldType.bodyMedium)
                    Text(account.username ?? account.providerType)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Sync Now", systemImage: "arrow.clockwise") {
                    onSyncNow()
                }
                .controlSize(.small)
                .disabled(isDeleting)

                Button(syncEnabled ? "Pause" : "Resume", systemImage: syncEnabled ? "pause" : "play") {
                    syncEnabled.toggle()
                }
                .controlSize(.small)
                .disabled(isDeleting)

                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Remove Account\u{2026}", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                    .controlSize(.small)
                    .help("Delete account and local mail data")
                    .accessibilityIdentifier("settings.mail.account.delete.\(account.accountID)")
                }
            }

            MailAccountHealthSection(
                account: account,
                progress: progress
            )
        }
        .padding(.vertical, 2)
    }

    private var provider: EmailProvider { account.provider }

    /// Provider glyph tinted with the provider's identity color. Provider
    /// identity colors are allowed here (they are not an agent palette
    /// collision — they signal "this is a Gmail mailbox" etc.).
    private var providerGlyph: some View {
        Image(systemName: provider.systemImage)
            .font(.title3)
            .foregroundStyle(providerTint)
            .accessibilityLabel("\(account.displayName), \(provider.rawValue)")
    }

    private var providerTint: Color {
        switch provider {
        case .gmail:    return .red
        case .outlook:  return .blue
        case .icloud:   return .cyan
        case .yahoo:    return .purple
        case .fastmail: return .indigo
        case .other:    return .secondary
        }
    }
}

private struct MailAccountHealthSection: View {
    let account: EmailAccountRecord
    let progress: MailSyncProgressSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            LabeledContent("Connection") {
                MailSyncStatusLabel(stage: progress?.stage, fallbackTitle: connectionText)
            }
            LabeledContent("Synced messages") {
                Text(MailSyncProgressPresentation.formattedCount(progress?.syncedMessageCount ?? 0))
                    .monospacedDigit()
            }
            LabeledContent("Mailboxes") {
                Text("\(progress?.mailboxSyncedCounts.count ?? 0)")
                    .monospacedDigit()
            }
            LabeledContent("Jobs") {
                Text(jobText)
            }
            LabeledContent("Last updated") {
                Text(MailSyncProgressPresentation.relativeTimestamp(progress?.lastUpdatedAt) ?? "Not yet")
            }
            if let error = progress?.errorMessage, !error.isEmpty {
                LabeledContent("Last error") {
                    Text(error)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .font(ManifoldType.caption)
    }

    private var connectionText: String {
        guard let progress else {
            return account.syncEnabled ? "Unknown" : "Paused"
        }
        return MailSyncProgressPresentation.stageTitle(progress.stage)
    }

    private var jobText: String {
        guard let progress else { return "No active jobs" }
        let running = progress.runningJobCount
        let queued = progress.queuedBackfillCount
        if running == 0 && queued == 0 {
            return "No active jobs"
        }
        return "\(running) running · \(queued) backfill queued"
    }
}

struct MailSyncStatusLabel: View {
    let stage: MailSyncProgressStage?
    var fallbackTitle = "Unknown"

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }

    private var title: String {
        stage.map(MailSyncProgressPresentation.stageTitle) ?? fallbackTitle
    }

    private var systemImage: String {
        stage.map(MailSyncProgressPresentation.stageSymbol) ?? "questionmark.circle"
    }
}
