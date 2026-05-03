// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

struct AddMailAccountSheet: View {
    @Environment(ManifoldStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(MailOnboardingProvider.allCases) { provider in
                NavigationLink(value: provider) {
                    MailProviderRow(provider: provider)
                }
                .accessibilityIdentifier(provider.accessibilityIdentifier)
            }
            .accessibilityIdentifier("settings.mail.addAccount.header")
            .navigationTitle("Connect a mailbox")
            .safeAreaInset(edge: .bottom) {
                Text("Manifold creates a local, read-only mail backup on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .navigationDestination(for: MailOnboardingProvider.self) { provider in
                EmailAccountSetupView(provider: provider.emailProvider) {
                    dismiss()
                }
                .environment(store)
            }
        }
        .frame(width: 520, height: 560)
    }
}

private struct MailProviderRow: View {
    let provider: MailOnboardingProvider

    var body: some View {
        HStack(spacing: 12) {
            MailProviderIcon(provider: provider)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.guide.displayLabel)
                Text(provider.guide.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MailProviderIcon: View {
    let provider: MailOnboardingProvider

    var body: some View {
        switch provider {
        case .google:
            Image("Google_\"G\"_logo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .accessibilityIdentifier("settings.mail.provider.google.logo")
        case .microsoft:
            Image("microsoft")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .accessibilityIdentifier("settings.mail.provider.microsoft.logo")
        case .icloud:
            Image(systemName: "icloud.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.mail.provider.icloud.logo")
        case .other:
            Image(systemName: "at")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.mail.provider.other.logo")
        }
    }
}
