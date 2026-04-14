// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LiveCheckRow — kept-as-shim for the Setup sheets that survived Phase 9.
// Matches the original call-site shape: label + status + optional
// action / action-label / refresh. The Stage-11 plan marks this for
// deletion, but ConnectClaudeSheet, ConnectCodexSheet, and
// AddMailAccountSheet are KEPT (visual refresh only). Full redesign
// lands with Setup's visual refresh in a subsequent minor pass.

import SwiftUI

struct LiveCheckRow: View {
    let label: String
    let status: AgentConnectionStatus
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    var onRefresh: (() async -> Void)? = nil

    @State private var refreshing = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(ManifoldType.body)
                Text(status.isPassingCheck ? "OK" : "\(status)")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let action, let actionLabel, !status.isPassingCheck {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let onRefresh {
                Button {
                    Task {
                        refreshing = true
                        await onRefresh()
                        refreshing = false
                    }
                } label: {
                    Image(systemName: refreshing ? "arrow.clockwise.circle" : "arrow.clockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        status.isPassingCheck ? "checkmark.circle.fill" : "circle"
    }

    private var iconColor: Color {
        status.isPassingCheck ? ManifoldPalette.active : ManifoldPalette.text3
    }
}

struct DetailLine: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(ManifoldType.captionMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(ManifoldType.caption)
                .foregroundStyle(ManifoldPalette.text)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
