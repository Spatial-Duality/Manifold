// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Drift review before reopening a historical session in Work.
struct ReloadDriftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ManifoldStore.self) private var store
    let historyEntry: SessionHistoryEntry
    @State private var isOpening = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack {
                Text("Session review").font(ManifoldType.heading)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            let drift = store.drift(for: historyEntry)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Label("Drift check", systemImage: "arrow.triangle.2.circlepath")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.active)
                Text("Manifold compares this historical session with the current scope before you reuse its context.")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                    .fill(ManifoldPalette.activeSoft)
            )

            DriftBanner(drift: drift)

            Divider()

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(historyEntry.name)
                    .font(ManifoldType.bodyMedium)
                Text("\(historyEntry.displayLastRun) · \(historyEntry.displayDuration)")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Open in Work") {
                    Task {
                        isOpening = true
                        errorMessage = nil
                        do {
                            try await store.reloadSession(historyID: historyEntry.id)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isOpening = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOpening)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.s5)
        .frame(width: 460)
    }
}

private struct DriftBanner: View {
    let drift: SessionDrift

    var body: some View {
        if drift.isClean {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(ManifoldPalette.active)
                Text("Your scope hasn't changed since this session ran.")
                    .font(ManifoldType.caption)
            }
            .padding(Spacing.s3)
            .background(RoundedRectangle(cornerRadius: Spacing.r3).fill(ManifoldPalette.activeSoft))
        } else {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Scope has drifted")
                    .font(ManifoldType.captionMedium)
                    .foregroundStyle(ManifoldPalette.attention)
                if !drift.pathsChangedSinceEnded.isEmpty {
                    Text("\(drift.pathsChangedSinceEnded.count) file(s) changed since this session ended.")
                        .font(ManifoldType.caption)
                }
                if !drift.pathsRevokedSinceEnded.isEmpty {
                    Text("\(drift.pathsRevokedSinceEnded.count) path(s) are no longer accessible.")
                        .font(ManifoldType.caption)
                }
                if !drift.newlyAddedSinceEnded.isEmpty {
                    Text("\(drift.newlyAddedSinceEnded.count) new folder(s) have been added since.")
                        .font(ManifoldType.caption)
                }
            }
            .padding(Spacing.s3)
            .background(RoundedRectangle(cornerRadius: Spacing.r3).fill(ManifoldPalette.attentionSoft))
        }
    }
}
