// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct MailSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @Binding var addAccountSheetPresented: Bool

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
                                syncEnabled: syncBinding(for: account)
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
                }
            }
            .formStyle(.grouped)
        }
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
    @Binding var syncEnabled: Bool

    var body: some View {
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

            Toggle("Sync \(account.displayName)", isOn: $syncEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var provider: EmailProvider { account.provider }

    /// Brand glyph tinted with the provider's identity color. Provider
    /// brand colors are allowed here (they are not an agent palette
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
