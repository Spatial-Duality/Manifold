import SwiftUI
import ManifoldKit

/// Email overview: connection status, mailboxes, classification summary.
struct EmailOverviewView: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        List {
            // Connection
            Section("Apple Mail") {
                HStack {
                    connectionIcon
                    connectionText
                    Spacer()
                    Button("Check") { Task { await store.checkMailAccess() } }
                        .controlSize(.small)
                }
            }

            // Mailboxes
            if !store.mailboxes.isEmpty {
                Section("Mailboxes") {
                    ForEach(store.mailboxes, id: \.name) { mailbox in
                        HStack {
                            Label("\(mailbox.account) / \(mailbox.name)", systemImage: "tray")
                            Spacer()
                            Text("\(mailbox.messageCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button("Fetch") {
                                Task { await store.fetchAndCacheEmails(account: mailbox.account, mailbox: mailbox.name) }
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            } else if store.mailAccessStatus == .available {
                Section {
                    Button("Load Mailboxes") { Task { await store.loadMailboxes() } }
                }
            }

            // Classification
            if let c = store.emailClassification {
                Section("Classification") {
                    LabeledContent("Shared") {
                        Text("\(c.shared)").foregroundStyle(.green).monospacedDigit()
                    }
                    LabeledContent("Auto-hidden") {
                        Text("\(c.autoHidden)").foregroundStyle(.orange).monospacedDigit()
                    }
                    LabeledContent("Total") {
                        Text("\(c.total)").monospacedDigit()
                    }
                    if !c.reasonBreakdown.isEmpty {
                        ForEach(Array(c.reasonBreakdown.sorted(by: { $0.value > $1.value })), id: \.key) { reason, count in
                            LabeledContent(reason) {
                                Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Email Overview")
        .task {
            await store.checkMailAccess()
            await store.reclassifyEmails()
        }
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch store.mailAccessStatus {
        case .available:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .mailNotRunning:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
        case .accessDenied:
            Image(systemName: "xmark.circle").foregroundStyle(.red)
        case nil:
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private var connectionText: some View {
        switch store.mailAccessStatus {
        case .available: Text("Connected")
        case .mailNotRunning: Text("Mail not running")
        case .accessDenied: Text("Permission needed")
        case nil: Text("Checking...")
        }
    }
}
