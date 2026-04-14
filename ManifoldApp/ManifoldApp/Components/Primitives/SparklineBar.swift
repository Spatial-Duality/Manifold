// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SparklineBar — compact bar-chart for session shape, event density,
// blast-radius previews.
//
// Values in 0..1, no axes, no labels. Used at row height (14–18pt). When
// a bar carries semantic weight (a denial, a write) the caller can mark
// it via `emphasis`. A sparkline is a hint, not a chart — keep it dense.

import SwiftUI

struct SparklineBar: View {
    struct Sample: Identifiable {
        let id = UUID()
        let value: Double                 // 0..1
        var emphasis: Emphasis = .base
    }
    enum Emphasis { case base, active, attention, muted }

    let samples: [Sample]
    var height: CGFloat = 14
    var tint: Color = ManifoldPalette.claude
    var spacing: CGFloat = 1.5
    var cornerRadius: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(samples) { sample in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(color(for: sample.emphasis))
                        .frame(height: max(1, geometry.size.height * CGFloat(sample.value)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true) // parent row provides the label
    }

    private func color(for emphasis: Emphasis) -> Color {
        switch emphasis {
        case .base:      return tint.opacity(0.62)
        case .active:    return tint
        case .attention: return ManifoldPalette.attention
        case .muted:     return ManifoldPalette.text3.opacity(0.5)
        }
    }
}

#Preview("Sparkline bars") {
    VStack(alignment: .leading, spacing: Spacing.s4) {
        SparklineBar(samples: (0..<24).map { i in
            let v = 0.25 + 0.5 * sin(Double(i) * 0.4) * 0.5 + 0.25
            return .init(value: max(0.05, min(1, v)))
        })
        SparklineBar(
            samples: [
                .init(value: 0.3),
                .init(value: 0.6, emphasis: .attention),
                .init(value: 0.45),
                .init(value: 0.9, emphasis: .active),
                .init(value: 0.2, emphasis: .muted),
                .init(value: 0.7, emphasis: .base),
            ],
            height: 18,
            tint: ManifoldPalette.codex
        )
    }
    .padding(Spacing.s6)
    .frame(width: 420)
    .background(ManifoldPalette.bg)
}
