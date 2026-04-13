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
            // Header
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Add Email Account").font(.title3.weight(.semibold))
                Text("Choose your email provider to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Provider selection
            ScrollView {
                VStack(spacing: Spacing.standard) {
                    providerButton(.gmail, icon: "envelope.fill", color: .red, label: "Gmail")
                    providerButton(.outlook, icon: "envelope.fill", color: .blue, label: "Outlook / Microsoft 365")
                    providerButton(.icloud, icon: "envelope.fill", color: .cyan, label: "iCloud Mail")
                    providerButton(.yahoo, icon: "envelope.fill", color: .purple, label: "Yahoo Mail")
                    providerButton(.other, icon: "server.rack", color: .secondary, label: "Other IMAP Server")
                }
                .padding(Spacing.edge)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(Spacing.edge)
        }
        .frame(width: 460, height: 440)
        .sheet(item: $selectedProvider) { _ in
            EmailAccountSetupView()
                .environment(store)
        }
    }

    private func providerButton(_ provider: EmailProvider, icon: String, color: Color, label: String) -> some View {
        Button {
            selectedProvider = provider
        } label: {
            HStack(spacing: Spacing.section) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(label)
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
            }
            .padding(Spacing.section)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

extension EmailProvider: @retroactive Identifiable {
    public var id: String { rawValue }
}
