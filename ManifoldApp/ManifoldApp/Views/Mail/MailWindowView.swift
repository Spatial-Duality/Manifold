// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailView — the mail surface.
//
// Active-Backup, not a Mail client. No reading pane, no compose, no reply.
// One surface: the dense review browser (sortable message table + narrow
// metadata inspector with atomic allow / hide). Account, mailbox, and quick
// filter navigation lives in the unified app sidebar.
//
// History: prior versions split this into Review / Session / History tabs.
// The Session and History tabs were stubs that pointed at functionality
// living elsewhere (Work handles cross-cutting history). Removing
// them per the redesign plan ships the Synology-style read-only archive
// view as the only surface and drops the dead tab bar that competed with
// the main app sidebar.
//
import SwiftUI
import ManifoldKit

enum MailSection: String, CaseIterable, Identifiable {
    case review
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: "Review"
        case .history: "History"
        }
    }

    var subtitle: String {
        switch self {
        case .review: "Share backed-up mail"
        case .history: "Shared-mail evidence"
        }
    }

    var systemImage: String {
        switch self {
        case .review: "envelope.badge"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct MailView: View {
    @Environment(ManifoldStore.self) private var store
    @Binding var section: MailSection
    @Binding var inspectorVisible: Bool
    @State private var hasLoadedMailAccounts = false

    var body: some View {
        VStack(spacing: 0) {
            if !hasLoadedMailAccounts {
                ProgressView("Loading mail backup…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ManifoldPalette.surface)
            } else if store.mailAccounts.accounts.isEmpty {
                EmptyMailView()
            } else {
                switch section {
                case .review:
                    MailReviewView(inspectorVisible: $inspectorVisible)
                case .history:
                    MailHistoryView()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .environment(store.mailAccounts)
        .environment(store.mailReview)
        .task {
            await store.mailAccounts.loadAccounts()
            await store.mailReview.prepare(force: true)
            hasLoadedMailAccounts = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ledger.surface.mail")
    }
}

private struct MailHistoryView: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(MailAccountsModel.self) private var mailAccounts
    @State private var rows: [MailHistoryRow] = []
    @State private var isLoading = true

    private var agents: [TargetApp] {
        AgentMeta.connected(from: store.connectedAgents)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mail History")
                        .font(ManifoldType.heading)
                    Text("\(rows.count) shared messages")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await loadRows() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)

            Divider()

            if isLoading {
                ProgressView("Loading shared mail…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No shared mail",
                    systemImage: "envelope",
                    description: Text("Messages shared from Mail Review appear here as evidence for each agent.")
                )
            } else {
                Table(rows) {
                    TableColumn("Agent") { row in
                        Label(row.agentLabel, systemImage: AgentMeta.systemImage(row.agent))
                            .font(ManifoldType.body)
                    }
                    .width(min: 100, ideal: 120, max: 180)

                    TableColumn("Subject") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.subject.isEmpty ? "(No subject)" : row.subject)
                                .font(ManifoldType.bodyMedium)
                                .lineLimit(1)
                            Text(row.sender)
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    TableColumn("Mailbox") { row in
                        Text(row.mailbox)
                    }
                    .width(min: 100, ideal: 140, max: 220)

                    TableColumn("Received") { row in
                        Text(row.receivedAt)
                    }
                    .width(min: 140, ideal: 170, max: 240)
                }
                .accessibilityIdentifier("mail.history.table")
            }
        }
        .task(id: AgentMeta.stableKey(agents)) {
            await loadRows()
        }
        .accessibilityIdentifier("mail.history")
    }

    @MainActor
    private func loadRows() async {
        isLoading = true
        var nextRows: [MailHistoryRow] = []
        for agent in agents {
            let messages = await mailAccounts.sharedEmails(agent: agent, limit: 500)
            nextRows.append(contentsOf: messages.map { MailHistoryRow(agent: agent, message: $0) })
        }
        rows = nextRows.sorted {
            if $0.receivedAt == $1.receivedAt {
                return $0.agentLabel < $1.agentLabel
            }
            return $0.receivedAt > $1.receivedAt
        }
        isLoading = false
    }
}

private struct MailHistoryRow: Identifiable {
    let id: String
    let agent: TargetApp
    let agentLabel: String
    let emailID: String
    let sender: String
    let subject: String
    let mailbox: String
    let receivedAt: String

    init(agent: TargetApp, message: EmailMessageRecord) {
        self.id = "\(agent.rawValue)-\(message.emailID)"
        self.agent = agent
        self.agentLabel = AgentMeta.label(agent)
        self.emailID = message.emailID
        self.sender = message.sender
        self.subject = message.subject
        self.mailbox = message.mailbox
        self.receivedAt = message.receivedAt
    }
}
