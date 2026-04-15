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
// thread's metadata only; the message body is never displayed.

import SwiftUI
import ManifoldKit

struct ThreadsView: View {
    @Environment(ManifoldStore.self) private var store

    @State private var senderFilter: SenderFilter = .all
    @State private var selectedThreadID: String? = nil

    enum SenderFilter: Hashable {
        case all
        case account(String)
        case trusted
        case ruleExcluded
    }

    var body: some View {
        VStack(spacing: 0) {
            SenderFilterStrip(filter: $senderFilter)
            Divider()

            HStack(spacing: 0) {
                ThreadTable(selection: $selectedThreadID)
                    .frame(maxWidth: .infinity)

                Divider()

                ThreadInspector(threadID: selectedThreadID)
                    .frame(width: 280)
                    .background(ManifoldPalette.surface2)
            }
        }
    }
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
    @Binding var selection: String?

    var body: some View {
        ContentUnavailableView {
            Label("No threads indexed yet", systemImage: "text.bubble")
        } description: {
            Text("Start a session and pick a mailbox — threads Claude reads during the session show up here with their sensitivity state.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Thread inspector

private struct ThreadInspector: View {
    let threadID: String?

    var body: some View {
        if threadID == nil {
            ContentUnavailableView(
                "No thread selected",
                systemImage: "sidebar.right",
                description: Text("Pick a thread on the left to see its metadata — subject line, first-line preview, and which agents have seen it.")
            )
        } else {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text("Thread metadata")
                    .font(ManifoldType.tiny.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Text("Metadata grid renders here when the mail-indexing pipeline lands.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s4)
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
