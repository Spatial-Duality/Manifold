// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Check row with inline refresh button for failed checks.
/// Used in connection sheets (Settings context). Each failed row
/// has a ↻ refresh icon instead of a footer "Check Again" button.
struct LiveCheckRow: View {
    let label: String
    let status: AgentConnectionStatus
    var action: (() -> Void)?
    var actionLabel: String?
    var onRefresh: (() async -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            statusIcon.frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body)
                Text(status.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(status.displayLabel)")

            Spacer()

            if status == .notInstalled || status == .error {
                if let actionLabel, let action {
                    Button(actionLabel, action: action)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }

                if let onRefresh {
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Check again")
                    .accessibilityLabel("Recheck \(label)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .connected, .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
                .accessibilityHidden(true)
        case .checking:
            ProgressView().controlSize(.small)
                .accessibilityLabel("Checking")
        case .notInstalled:
            Image(systemName: "circle")
                .font(.title2).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .unknown, .configured:
            Image(systemName: "circle.dashed")
                .font(.title2).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
