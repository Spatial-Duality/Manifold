// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailSettingsPane — the mailboxes + storage settings pane.
//
// Stage-11 redesign:
//   - Empty state uses ContentUnavailableView (references/design.md).
//   - Sync toggle binding extracted into syncBinding(for:) — no more
//     inline Binding(get:set:) in view body.
//   - Storage row uses the shared PathLabel primitive.
//   - Type and palette tokens migrated to ManifoldType / ManifoldPalette.

import SwiftUI
import ManifoldKit

struct MailSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var showAddAccount = false

    var body: some View {
        Form {
            Section("Accounts") {
                if store.emailAccounts.accounts.isEmpty {
                    ContentUnavailableView(
                        "No mailboxes connected",
                        systemImage: "envelope.badge",
                        description: Text("Connect a mailbox so Claude or Codex can see subject lines — or trusted-sender bodies — during a session.")
                    )
                    .padding(.vertical, Spacing.s4)
                } else {
                    ForEach(store.emailAccounts.accounts) { account in
                        MailAccountRow(
                            account: account,
                            syncEnabled: syncBinding(for: account)
                        )
                    }
                }

                Button("Connect a mailbox\u{2026}", systemImage: "plus") {
                    showAddAccount = true
                }
                .controlSize(.small)
            }

            Section("Storage") {
                LabeledContent("Backup location") {
                    PathLabel(store.emailAccounts.backupRootPath)
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

    /// Stable sync-state binding per account. Replaces the prior inline
    /// Binding(get:set:) per references/data.md.
    private func syncBinding(for account: EmailAccountRecord) -> Binding<Bool> {
        Binding(
            get: { account.syncEnabled },
            set: { enabled in
                Task {
                    await store.emailAccounts.toggleSync(
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
        case .outlook:  return ManifoldPalette.claude
        case .icloud:   return .cyan
        case .yahoo:    return ManifoldPalette.codex
        case .fastmail: return .indigo
        case .other:    return .secondary
        }
    }
}
