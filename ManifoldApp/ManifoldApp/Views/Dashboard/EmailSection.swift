import SwiftUI
import ManifoldKit

struct EmailSection: View {
    @Environment(ManifoldStore.self) var store

    private var accountCount: Int { store.emailAccounts.accounts.count }

    private var totalMessages: Int {
        store.emailAccounts.syncStates.values.flatMap { $0 }.reduce(0) { $0 + $1.messageCount }
    }

    private var isSyncing: Bool {
        store.emailAccounts.syncStates.values.flatMap { $0 }.contains { $0.syncStatus == .syncing }
    }

    private var hasError: Bool {
        store.emailAccounts.syncStates.values.flatMap { $0 }.contains { $0.syncStatus == .error }
    }

    var body: some View {
        Section("Email Backup") {
            if accountCount == 0 {
                HStack(spacing: Spacing.section) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No email accounts")
                            .font(.callout.weight(.medium))
                        Text("Add an account to start continuous email backup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") {
                        store.selectedSidebarItem = .emails
                    }
                    .controlSize(.small)
                }
            } else {
                LabeledContent("Accounts") {
                    HStack(spacing: Spacing.standard) {
                        Text("\(accountCount)")
                            .monospacedDigit()
                        if isSyncing {
                            ProgressView().controlSize(.mini)
                        } else if hasError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .imageScale(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                        }
                    }
                }

                LabeledContent("Messages backed up") {
                    Text("\(totalMessages)")
                        .monospacedDigit()
                }
            }
        }
    }
}
