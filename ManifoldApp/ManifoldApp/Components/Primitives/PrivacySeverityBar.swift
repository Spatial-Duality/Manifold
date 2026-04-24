// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PrivacySeverityBar — compact five-segment severity indicator.
//
// Reads like a signal-strength meter: segments light up as severity climbs
// (none → low → medium → high → critical). Color channel reinforces rank
// (text / selection / paused / attention / danger) per Principle 6
// (color-as-state is a second channel — the fill count carries meaning too).

import SwiftUI
import ManifoldKit

struct PrivacySeverityBar: View {
    let severity: PrivacySeverity
    var showLabel: Bool = true

    private var activeCount: Int {
        switch severity {
        case .none:     return 0
        case .low:      return 1
        case .medium:   return 2
        case .high:     return 3
        case .critical: return 4
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s2) {
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(index < activeCount ? Self.color(for: severity) : ManifoldPalette.border)
                        .frame(width: 6, height: CGFloat(8 + index * 3))
                }
            }
            if showLabel {
                Text(label)
                    .font(ManifoldType.tiny)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(Self.color(for: severity))
            }
        }
        .accessibilityLabel("Privacy severity: \(label)")
    }

    private var label: String {
        switch severity {
        case .none:     return "None"
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }

    static func color(for severity: PrivacySeverity) -> Color {
        switch severity {
        case .none:     return ManifoldPalette.text3
        case .low:      return ManifoldPalette.selection
        case .medium:   return ManifoldPalette.paused
        case .high:     return ManifoldPalette.attention
        case .critical: return ManifoldPalette.danger
        }
    }
}

#Preview("PrivacySeverityBar") {
    VStack(alignment: .leading, spacing: Spacing.s3) {
        ForEach(PrivacySeverity.allCases, id: \.self) { severity in
            PrivacySeverityBar(severity: severity)
        }
    }
    .padding(Spacing.s5)
    .background(ManifoldPalette.bg)
}
