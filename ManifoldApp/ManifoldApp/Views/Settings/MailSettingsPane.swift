// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct MailSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showAddAccount = false

    var body: some View {
        Form {
            Section("Accounts") {
                if store.emailAccounts.accounts.isEmpty {
                    Text("No email accounts configured.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.emailAccounts.accounts) { account in
                        HStack(spacing: Spacing.standard) {
                            Image(systemName: account.provider.systemImage)
                                .foregroundStyle(providerColor(account.provider))
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(Typ.body.weight(.medium))
                                Text(account.username ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("Sync", isOn: Binding(
                                get: { account.syncEnabled },
                                set: { enabled in
                                    Task { await store.emailAccounts.toggleSync(accountID: account.accountID, enabled: enabled) }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }
                    }
                }

                Button("Add Email Account\u{2026}") { showAddAccount = true }
                    .controlSize(.small)
            }

            Section("Storage") {
                LabeledContent("Backup location") {
                    Text(store.emailAccounts.backupRootPath)
                        .font(Typ.mono)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Total messages") {
                    Text("\(store.emailAccounts.totalMessageCount)")
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddAccount) {
            AddMailAccountSheet()
                .environment(store)
        }
    }

    private func providerColor(_ provider: EmailProvider) -> Color {
        switch provider {
        case .gmail: .red
        case .outlook: .blue
        case .icloud: .cyan
        case .yahoo: .purple
        case .fastmail: .indigo
        case .other: .secondary
        }
    }
}
