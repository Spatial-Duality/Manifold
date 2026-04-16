// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MailboxesMatrixView — mailbox × agent × sensitivity matrix.
//
// Per design/html/mail.html view 1: each row is a mailbox the user has
// connected; each agent column shows the current sensitivity level with
// a 3-option segmented control ("Subjects only / Trusted senders / Full").

import SwiftUI
import ManifoldKit

struct MailboxesMatrixView: View {
    @Environment(ManifoldStore.self) private var store
    @State private var selectedAccountID: String?

    var body: some View {
        HStack(spacing: 0) {
            // Matrix
            VStack(spacing: 0) {
                List(selection: $selectedAccountID) {
                    ForEach(store.emailAccounts.accounts) { account in
                        MailboxRow(account: account)
                            .tag(account.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Inspector
            MailboxInspector(selection: selectedAccountID, store: store)
                .frame(width: 300)
                .background(ManifoldPalette.surface2)
        }
    }
}

private struct MailboxRow: View {
    let account: EmailAccountRecord

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "envelope")
                .font(.title3)
                .foregroundStyle(ManifoldPalette.codex)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(ManifoldType.bodyMedium)
                Text(account.username ?? account.providerType)
                    .font(ManifoldType.mono)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, Spacing.s1)
    }
}

/// The 3-option sensitivity selector — "what Manifold lets Claude see"
/// for a mailbox. Subjects-only is the default (Stage 8 Active Backup).
struct SensitivitySelector: View {
    enum Level: String, Hashable, CaseIterable {
        case subjects, trusted, full

        var label: String {
            switch self {
            case .subjects: return "Subjects only"
            case .trusted:  return "Trusted senders"
            case .full:     return "Full content"
            }
        }
    }

    @Binding var level: Level

    var body: some View {
        SegmentedToggle(
            selection: $level,
            options: Level.allCases.map { lvl in
                SegmentedToggle<Level>.Option(
                    value: lvl,
                    label: lvl.label,
                    tint: tint(for: lvl)
                )
            }
        )
    }

    private func tint(for level: Level) -> Color {
        switch level {
        case .subjects: return ManifoldPalette.claude
        case .trusted:  return ManifoldPalette.active
        case .full:     return ManifoldPalette.attention
        }
    }
}

struct MailboxInspector: View {
    let selection: String?
    let store: ManifoldStore

    private var account: EmailAccountRecord? {
        guard let selection else { return nil }
        return store.emailAccounts.accounts.first(where: { $0.id == selection })
    }

    var body: some View {
        ScrollView {
            if let account {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(account.displayName)
                        .font(ManifoldType.heading)
                    Text(account.username ?? account.providerType)
                        .font(ManifoldType.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Divider()

                    // Sensitivity selector is NOT rendered until the
                    // per-mailbox sensitivity state is backed by
                    // PolicyStore. Showing a SegmentedToggle that
                    // pretends to mutate runtime while silently doing
                    // nothing is the §3.3 fake signal Priority 3 calls
                    // out. Honest placeholder until the wiring lands.
                    Text("Sensitivity")
                        .font(ManifoldType.tiny.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    HStack(alignment: .top, spacing: Spacing.s2) {
                        Image(systemName: "bolt.slash")
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Configuration not wired yet")
                                .font(ManifoldType.bodyMedium)
                                .foregroundStyle(.secondary)
                            Text("Per-mailbox sensitivity (subjects / trusted senders / full) will land here once the runtime exposes a per-mailbox policy surface. Until then, all mailboxes default to subjects-only.")
                                .font(ManifoldType.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Spacing.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                            .fill(ManifoldPalette.surface3.opacity(0.5))
                    )
                }
                .padding(Spacing.s4)
            } else {
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "tray.2")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a mailbox to see its metadata.")
                        .font(ManifoldType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.s8)
            }
        }
    }
}
