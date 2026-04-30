// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PrivacyApprovalButtons: View {
    var onDeny: () -> Void = {}
    var onShareRedacted: () -> Void = {}
    var onShareOriginal: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Button("Deny", action: onDeny)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ManifoldPalette.attention)
                .accessibilityIdentifier("requests.action.deny")

            Button("Share Redacted", action: onShareRedacted)
                .keyboardShortcut(.return, modifiers: .shift)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(ManifoldPalette.active)
                .accessibilityIdentifier("requests.action.shareRedacted")

            Button("Share Original Once", action: onShareOriginal)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("requests.action.shareOriginalOnce")
        }
    }
}
