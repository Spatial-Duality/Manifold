// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

/// Provider-first email account setup sheet.
/// Wraps the existing EmailAccountSetupView in a provider selection flow.
struct AddMailAccountSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: EmailProvider?

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Connect a mailbox",
                subtitle: "Pick the account type Manifold should sync into its local mail backup.",
                systemImage: "envelope.badge.shield.half.filled",
                accent: ManifoldPalette.claude
            )
            .accessibilityIdentifier("settings.mail.addAccount.header")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text("Provider")
                        .font(ManifoldType.tiny)
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(ManifoldPalette.text2)

                    providerButton(.gmail, icon: "envelope.fill", color: .red, label: "Gmail")
                    providerButton(.outlook, icon: "envelope.fill", color: .blue, label: "Outlook / Microsoft 365")
                    providerButton(.icloud, icon: "envelope.fill", color: .cyan, label: "iCloud Mail")
                    providerButton(.yahoo, icon: "envelope.fill", color: .purple, label: "Yahoo Mail")
                    providerButton(.fastmail, icon: "paperplane.fill", color: .indigo, label: "Fastmail")
                    providerButton(.other, icon: "server.rack", color: .secondary, label: "Other IMAP Server")
                }
                .padding(Spacing.s5)
            }
            .background(ManifoldPalette.bg)

            Divider()

            SettingsSheetFooter {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 460, height: 440)
        .sheet(item: $selectedProvider) { provider in
            EmailAccountSetupView(provider: provider) {
                selectedProvider = nil
                dismiss()
            }
                .environment(store)
        }
    }

    private func providerButton(_ provider: EmailProvider, icon: String, color: Color, label: String) -> some View {
        Button {
            selectedProvider = provider
        } label: {
            HStack(spacing: Spacing.section) {
                SettingsSymbolTile(systemImage: icon, accent: color, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(ManifoldType.bodyMedium)
                        .foregroundStyle(ManifoldPalette.text)
                    Text(provider.detail)
                        .font(ManifoldType.caption)
                        .foregroundStyle(ManifoldPalette.text2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
            }
            .padding(Spacing.s3)
            .background(ManifoldPalette.surface, in: RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.mail.provider.\(provider.rawValue)")
    }
}

extension EmailProvider: @retroactive Identifiable {
    public var id: String { rawValue }
}

private extension EmailProvider {
    var detail: String {
        switch self {
        case .gmail:
            return "imap.gmail.com"
        case .outlook:
            return "Microsoft 365 and Outlook IMAP"
        case .icloud:
            return "iCloud Mail app-password flow"
        case .yahoo:
            return "Yahoo Mail IMAP"
        case .fastmail:
            return "Fastmail IMAP"
        case .other:
            return "Custom host, port, and credentials"
        }
    }
}
