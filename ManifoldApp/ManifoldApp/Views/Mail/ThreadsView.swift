// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ThreadsView — the Active-Backup thread view.
//
// Revised layout: two-column (table + inspector). A compact horizontal
// sender-filter strip sits above the table — the previous nested
// "sidebar"-styled List collided with the outer NavigationSplitView on
// narrow windows (the outer sidebar auto-collapsed and the inner List
// rendered empty). The filter strip carries the same affordances —
// Accounts, Smart filters — in a form that never competes with the
// window's real sidebar.
//
// Stage-8 posture: no reading pane. The inspector shows the selected
// message's metadata only; the body is never rendered inline. Space →
// QuickLook the raw .eml (Finder-parity peek); ⌘↩ → NSWorkspace.open
// hands the file to the user's default mail client. Both affordances
// are conditional on emlPath existing on disk — Principle 10 forbids
// a button that pretends to open a file we don't actually have.

import SwiftUI
import AppKit
import QuickLook
import ManifoldKit

struct ThreadsView: View {
    @Environment(ManifoldStore.self) private var store

    @State private var senderFilter: SenderFilter = .all
    @State private var selectedMessageID: String? = nil
    @State private var messages: [EmailMessageRecord] = []
    @State private var quickLookURL: URL? = nil
    @State private var loadToken: Int = 0
    @State private var isSyncing: Bool = false

    enum SenderFilter: Hashable {
        case all
        case account(String)
        case trusted
        case ruleExcluded
    }

    /// Honest classification of why the thread table is empty. The
    /// previous single "No messages in this filter" copy was dishonest
    /// for two of the four cases — Principle 10.
    enum EmptyReason {
        /// Accounts exist but no messages have been synced to the local
        /// store yet. Offer a Sync Now action.
        case nothingSyncedYet
        /// The filter is a placeholder that the runtime doesn't resolve
        /// yet (trusted senders, rule-excluded). Say so plainly.
        case filterNotWired
        /// The DB has messages; this filter genuinely returns none.
        case noMatchForFilter
    }

    var body: some View {
        VStack(spacing: 0) {
            SenderFilterStrip(filter: $senderFilter)
            Divider()

            HStack(spacing: 0) {
                ThreadTable(
                    messages: messages,
                    selection: $selectedMessageID,
                    emptyReason: emptyReason,
                    isSyncing: isSyncing,
                    onSyncNow: syncAllAccounts
                )
                .frame(maxWidth: .infinity)

                Divider()

                ThreadInspector(
                    message: selectedMessage,
                    onQuickLook: presentQuickLook,
                    onOpenInDefaultClient: openInDefaultClient
                )
                .frame(width: 300)
                .background(ManifoldPalette.surface2)
            }
        }
        .quickLookPreview($quickLookURL)
        .task(id: loadKey) { await reload() }
    }

    /// Which empty state to show when `messages` is empty. Computed so the
    /// copy stays honest for every combination of filter + DB state.
    private var emptyReason: EmptyReason {
        switch senderFilter {
        case .trusted, .ruleExcluded:
            return .filterNotWired
        case .all, .account:
            // `totalMessageCount` is the *global* DB count and doesn't
            // change with the filter. If the DB is globally empty then
            // no filter can match; the user needs a sync, not a
            // different filter.
            return store.emailAccounts.totalMessageCount == 0
                ? .nothingSyncedYet
                : .noMatchForFilter
        }
    }

    private func syncAllAccounts() {
        let accounts = store.emailAccounts.accounts
        guard !accounts.isEmpty else { return }
        Task {
            isSyncing = true
            defer { isSyncing = false }
            for account in accounts {
                await store.emailAccounts.syncNow(accountID: account.accountID)
            }
            await reload()
        }
    }

    private var selectedMessage: EmailMessageRecord? {
        guard let id = selectedMessageID else { return nil }
        return messages.first { $0.emailID == id }
    }

    /// Reload token that changes whenever the filter or upstream account
    /// list changes; the .task(id:) observer re-runs on change.
    private var loadKey: String {
        switch senderFilter {
        case .all:                return "all-\(store.emailAccounts.mailboxRefreshToken)"
        case .account(let id):    return "acct-\(id)-\(store.emailAccounts.mailboxRefreshToken)"
        case .trusted:            return "trusted-\(store.emailAccounts.mailboxRefreshToken)"
        case .ruleExcluded:       return "ruleExcluded-\(store.emailAccounts.mailboxRefreshToken)"
        }
    }

    private func reload() async {
        let next: [EmailMessageRecord]
        switch senderFilter {
        case .all:
            next = await store.emailAccounts.allMessages(limit: 500)
        case .account(let accountID):
            next = await store.emailAccounts.messages(accountID: accountID, limit: 500)
        case .trusted, .ruleExcluded:
            // These filters require sensitivity + rule resolution that
            // the runtime hasn't exposed to the app yet; render empty
            // honestly instead of faking a subset.
            next = []
        }
        messages = next
        if let sel = selectedMessageID, !messages.contains(where: { $0.emailID == sel }) {
            selectedMessageID = nil
        }
        loadToken &+= 1
    }

    private func presentQuickLook() {
        guard let message = selectedMessage,
              let url = openableEMLURL(for: message) else { return }
        quickLookURL = url
    }

    private func openInDefaultClient() {
        guard let message = selectedMessage,
              let url = openableEMLURL(for: message) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The on-disk URL for a message's raw `.eml`, if and only if the file
/// actually exists. Returning nil when the path is missing lets callers
/// disable their affordances honestly.
func openableEMLURL(for message: EmailMessageRecord) -> URL? {
    guard let path = message.emlPath, !path.isEmpty else { return nil }
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return URL(fileURLWithPath: path)
}

// MARK: - Sender filter strip

private struct SenderFilterStrip: View {
    @Environment(ManifoldStore.self) private var store
    @Binding var filter: ThreadsView.SenderFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s2) {
                FilterChip(
                    label: "All",
                    systemImage: "tray.full",
                    tint: ManifoldPalette.claude,
                    isSelected: filter == .all,
                    action: { filter = .all }
                )

                if !store.emailAccounts.accounts.isEmpty {
                    Divider().frame(height: 18)
                    ForEach(store.emailAccounts.accounts) { account in
                        FilterChip(
                            label: account.displayName,
                            systemImage: "envelope",
                            tint: ManifoldPalette.codex,
                            isSelected: filter == .account(account.accountID),
                            action: { filter = .account(account.accountID) }
                        )
                    }
                }

                Divider().frame(height: 18)

                FilterChip(
                    label: "Trusted senders",
                    systemImage: "star.fill",
                    tint: ManifoldPalette.paused,
                    isSelected: filter == .trusted,
                    action: { filter = .trusted }
                )
                FilterChip(
                    label: "Rule-excluded",
                    systemImage: "exclamationmark.shield.fill",
                    tint: ManifoldPalette.attention,
                    isSelected: filter == .ruleExcluded,
                    action: { filter = .ruleExcluded }
                )
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FilterChip: View {
    let label: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(ManifoldType.captionMedium)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? tint.opacity(0.14) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? tint.opacity(0.35) : ManifoldPalette.border,
                            lineWidth: 0.6
                        )
                )
                .foregroundStyle(isSelected ? tint : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Thread table

private struct ThreadTable: View {
    let messages: [EmailMessageRecord]
    @Binding var selection: String?
    let emptyReason: ThreadsView.EmptyReason
    let isSyncing: Bool
    let onSyncNow: () -> Void

    var body: some View {
        if messages.isEmpty {
            emptyStateView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(messages, selection: $selection) {
                TableColumn("Subject") { message in
                    Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                TableColumn("Sender") { message in
                    Text(message.sender)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 200)
                TableColumn("Mailbox") { message in
                    Text(message.mailbox)
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 140)
                TableColumn("Received") { message in
                    Text(formatReceivedAt(message.receivedAt))
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 140)
            }
        }
    }

    /// Honest empty state per `emptyReason`. No filter should ever show
    /// a generic "no messages" shrug — each reason names itself and,
    /// where a user action would help, offers it.
    @ViewBuilder
    private var emptyStateView: some View {
        switch emptyReason {
        case .nothingSyncedYet:
            ContentUnavailableView {
                Label("No mail synced yet", systemImage: "tray")
            } description: {
                Text("Accounts are connected, but Manifold hasn't pulled any messages into its local store. Sync an account to populate the Threads view.")
            } actions: {
                Button(action: onSyncNow) {
                    if isSyncing {
                        HStack(spacing: Spacing.s2) {
                            ProgressView().controlSize(.small)
                            Text("Syncing…")
                        }
                    } else {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncing)
            }

        case .filterNotWired:
            ContentUnavailableView {
                Label("Not wired up yet", systemImage: "hammer")
            } description: {
                Text("This filter resolves against sensitivity and rule data that the runtime doesn't expose to the app yet. Pick an account or 'All' to see synced messages.")
            }

        case .noMatchForFilter:
            ContentUnavailableView {
                Label("No messages match this filter", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a different account or 'All'. Messages that are synced to this account don't match the current filter.")
            }
        }
    }

    /// Hoisted formatter — `ISO8601DateFormatter` is expensive to construct
    /// and this runs once per visible row on every table render.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback formatter for timestamps without fractional seconds.
    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func formatReceivedAt(_ iso: String) -> String {
        if let date = Self.isoFormatter.date(from: iso)
            ?? Self.isoFormatterNoFrac.date(from: iso) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso
    }
}

// MARK: - Thread inspector

private struct ThreadInspector: View {
    let message: EmailMessageRecord?
    let onQuickLook: () -> Void
    let onOpenInDefaultClient: () -> Void

    var body: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text("Message")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                        .font(ManifoldType.bodyMedium)

                    MetadataGrid(message: message)

                    Divider().padding(.vertical, Spacing.s1)

                    ActionButtons(
                        message: message,
                        onQuickLook: onQuickLook,
                        onOpenInDefaultClient: onOpenInDefaultClient
                    )

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
            }
        } else {
            ContentUnavailableView(
                "No message selected",
                systemImage: "sidebar.right",
                description: Text("Pick a message on the left to see its metadata and peek at the raw .eml.")
            )
        }
    }
}

private struct MetadataGrid: View {
    let message: EmailMessageRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            MetadataRow(label: "From",     value: message.sender)
            MetadataRow(label: "Mailbox",  value: message.mailbox)
            MetadataRow(label: "Received", value: message.receivedAt)
            if !message.recipients.isEmpty {
                MetadataRow(label: "To", value: message.recipients)
            }
            if message.attachmentCount > 0 {
                MetadataRow(
                    label: "Attachments",
                    value: "\(message.attachmentCount) — open the .eml to access"
                )
            }
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(label)
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(ManifoldType.caption)
                .textSelection(.enabled)
        }
    }
}

private struct ActionButtons: View {
    let message: EmailMessageRecord
    let onQuickLook: () -> Void
    let onOpenInDefaultClient: () -> Void

    private var canOpen: Bool { openableEMLURL(for: message) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            // ⌘↩ primary — open in default mail client.
            Button {
                onOpenInDefaultClient()
            } label: {
                Label("Open in Default Mail Client", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canOpen)

            // Space-keyed peek — QuickLook.
            Button {
                onQuickLook()
            } label: {
                Label("Preview (Space)", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!canOpen)

            if !canOpen {
                Text("The raw .eml for this message isn't on disk — Manifold can't peek or hand it off.")
                    .font(ManifoldType.tiny)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.s1)
            }
        }
    }
}

// MARK: - Adjacent tab bodies

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
                    Text("Mailbox additions, removals, and inherited scope land here when the mail-session pipeline is wired end-to-end.")
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

struct MailHistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No mail sessions yet",
            systemImage: "clock.arrow.circlepath",
            description: Text("Finished mail sessions show up here with the mailboxes they touched and how many threads they read.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
