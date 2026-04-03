import SwiftUI
import ManifoldKit

struct EmailsView: View {
    @EnvironmentObject var store: ManifoldStore
    @State private var selectedTab = "overview"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Overview").tag("overview")
                Text("Emails").tag("emails")
                Text("Rules").tag("rules")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case "overview": EmailOverviewTab()
            case "emails": EmailListView()
            case "rules": EmailRulesView()
            default: EmptyView()
            }
        }
        .navigationTitle("Emails")
        .task {
            await store.checkMailAccess()
            await store.loadEmailRules()
            await store.loadCachedEmails()
            await store.reclassifyEmails()
        }
    }
}

// MARK: - Overview Tab

struct EmailOverviewTab: View {
    @EnvironmentObject var store: ManifoldStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Connection Status
                GroupBox("Apple Mail Connection") {
                    HStack {
                        switch store.mailAccessStatus {
                        case .available:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Connected to Apple Mail")
                        case .mailNotRunning:
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow)
                            Text("Mail.app is not running")
                        case .accessDenied:
                            Image(systemName: "xmark.circle").foregroundStyle(.red)
                            Text("Automation permission needed")
                        case nil:
                            ProgressView().controlSize(.small)
                            Text("Checking...")
                        }
                        Spacer()
                        Button("Check Again") {
                            Task { await store.checkMailAccess() }
                        }
                        .controlSize(.small)
                    }
                    .padding(4)
                }

                // Mailboxes
                if !store.mailboxes.isEmpty {
                    GroupBox("Mailboxes") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.mailboxes, id: \.name) { mailbox in
                                HStack {
                                    Text("\(mailbox.account) / \(mailbox.name)")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(mailbox.messageCount) messages")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button("Fetch") {
                                        Task {
                                            await store.fetchAndCacheEmails(
                                                account: mailbox.account,
                                                mailbox: mailbox.name
                                            )
                                        }
                                    }
                                    .controlSize(.mini)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(4)
                    }
                } else if store.mailAccessStatus == .available {
                    Button("Load Mailboxes") {
                        Task { await store.loadMailboxes() }
                    }
                    .buttonStyle(.bordered)
                }

                // Classification Summary
                if let classification = store.emailClassification {
                    GroupBox("Classification") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                VStack {
                                    Text("\(classification.shared)")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.green)
                                    Text("Shared").font(.caption)
                                }
                                VStack {
                                    Text("\(classification.autoHidden)")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.yellow)
                                    Text("Hidden").font(.caption)
                                }
                                VStack {
                                    Text("\(classification.total)")
                                        .font(.title2.weight(.semibold))
                                    Text("Total").font(.caption)
                                }
                            }

                            if !classification.reasonBreakdown.isEmpty {
                                Divider()
                                ForEach(Array(classification.reasonBreakdown.sorted(by: { $0.value > $1.value })), id: \.key) { reason, count in
                                    HStack {
                                        Text(reason).font(.caption)
                                        Spacer()
                                        Text("\(count)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
        }
    }
}
