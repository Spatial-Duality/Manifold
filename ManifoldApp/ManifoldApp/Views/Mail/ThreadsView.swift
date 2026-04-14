// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ThreadsView — the Active-Backup thread table.
//
// Stage-8 posture: dense 3-line-max rows with sender disc, sender+subject
// stack, date, agents, and a session-green/default-blue checkbox marking
// whether the thread is currently visible to the selected agent.
// No reading pane.

import SwiftUI
import ManifoldKit

struct ThreadsView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            SenderRail()
                .frame(width: 200)
                .background(ManifoldPalette.surface2)

            Divider()

            ThreadTable()
                .frame(maxWidth: .infinity)

            Divider()

            ThreadInspector()
                .frame(width: 280)
                .background(ManifoldPalette.surface2)
        }
    }
}

private struct SenderRail: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        List {
            Section("Accounts") {
                ForEach(store.emailAccounts.accounts) { account in
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: "envelope").foregroundStyle(ManifoldPalette.codex)
                        Text(account.displayName).font(ManifoldType.body)
                    }
                }
            }

            Section("Top senders") {
                Text("Populated once a session indexes mail")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Smart filters") {
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(ManifoldPalette.paused)
                    Text("Trusted senders")
                }.font(ManifoldType.body)
                HStack {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(ManifoldPalette.attention)
                    Text("Rule-excluded")
                }.font(ManifoldType.body)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ThreadTable: View {
    var body: some View {
        VStack {
            EmptyStateIllustration(
                systemImage: "text.bubble",
                title: "No threads indexed yet",
                subtitle: "Start a session and pick a mailbox — threads Claude reads during the session show up here with their sensitivity state."
            )
        }
        .frame(maxHeight: .infinity)
        .padding(Spacing.s6)
    }
}

private struct ThreadInspector: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Subject line + first-line preview + metadata grid live here for the selected thread.")
                .font(ManifoldType.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("No reading pane — this is Active Backup, not a Mail client.")
                .font(ManifoldType.caption)
                .foregroundStyle(.tertiary)
                .italic()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s4)
    }
}

struct MailSessionView: View {
    @Environment(ManifoldStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if let session = store.activeSession {
                    SessionChip(name: session.name,
                                remainingSeconds: session.remainingSeconds,
                                isTrackedEdit: session.isTrackedEdit)
                    Text("Mailbox additions, removals, and inherited scope land here once Phase 5 wires the mail session pipeline.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                } else {
                    EmptyStateIllustration(
                        systemImage: "play.circle",
                        title: "No session running",
                        subtitle: "Mail-scope changes are layered on top of the default whenever a session is live."
                    )
                }
            }
            .padding(Spacing.s4)
        }
    }
}

struct MailHistoryView: View {
    var body: some View {
        EmptyStateIllustration(
            systemImage: "clock.arrow.circlepath",
            title: "No mail sessions yet",
            subtitle: "Finished mail sessions show up here with the mailboxes they touched and how many threads they read."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s6)
    }
}
