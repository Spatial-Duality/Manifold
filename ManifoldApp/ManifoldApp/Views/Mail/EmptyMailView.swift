// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyMailView — no mailboxes connected. Provider chips let the user
// connect Gmail / iCloud / Outlook / IMAP. Drag-and-drop an mbox file
// is the power-user alt.

import SwiftUI
import ManifoldKit

struct EmptyMailView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedProvider: EmailProvider?

    var body: some View {
        VStack(spacing: Spacing.s6) {
            EmptyStateIllustration(
                systemImage: "tray.2",
                title: "No mailboxes connected",
                subtitle: "Connect a mailbox so you can review backed-up mail and share individual messages with confidence.",
                tint: ManifoldPalette.selection,
                style: .brandMark
            )

            HStack(spacing: Spacing.s2) {
                ProviderChip(name: "Gmail", systemImage: "g.circle.fill") {
                    selectedProvider = .gmail
                }
                ProviderChip(name: "iCloud", systemImage: "icloud.fill") {
                    selectedProvider = .icloud
                }
                ProviderChip(name: "Outlook", systemImage: "o.circle.fill") {
                    selectedProvider = .outlook
                }
                ProviderChip(name: "Other\u{00A0}IMAP", systemImage: "envelope.circle") {
                    selectedProvider = .other
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s8)
        .background(ManifoldPalette.bg)
        .accessibilityIdentifier("mail.empty")
        .sheet(item: $selectedProvider) { provider in
            EmailAccountSetupView(provider: provider) {
                selectedProvider = nil
            }
            .environment(store)
        }
    }
}

private struct ProviderChip: View {
    let name: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s1) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(ManifoldPalette.selection)
                Text(name)
                    .font(ManifoldType.captionMedium)
            }
            .padding(Spacing.s3)
            .frame(width: 88, height: 72)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(ManifoldPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
