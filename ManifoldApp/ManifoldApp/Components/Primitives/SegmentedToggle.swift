// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// SegmentedToggle — confident slot toggle.
//
// A small segmented control where each segment carries a semantic tint
// (default / session / attention). Different from SwiftUI's Picker —
// this variant lets us keep every option's tint channel distinct, per
// Principle 6.

import SwiftUI

struct SegmentedToggle<Value: Hashable>: View {
    struct Option: Identifiable {
        let id = UUID()
        let value: Value
        let label: String
        var tint: Color = ManifoldPalette.claude
        var systemImage: String?
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: Spacing.s1) {
                        if let image = option.systemImage {
                            Image(systemName: image)
                                .font(ManifoldType.captionMedium)
                        }
                        Text(option.label)
                            .font(ManifoldType.captionMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                                    .fill(option.tint.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                                            .strokeBorder(option.tint.opacity(0.35), lineWidth: 0.8)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: Spacing.r2, style: .continuous)
                                    .fill(Color.clear)
                            }
                        }
                    )
                    .foregroundStyle(
                        selection == option.value ? option.tint : Color.secondary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Spacing.r3, style: .continuous)
                .fill(ManifoldPalette.surface3.opacity(0.6))
        )
    }
}

#Preview("Segmented toggle") {
    struct Demo: View {
        @SwiftUI.State private var selection: String = "default"
        var body: some View {
            VStack(spacing: Spacing.s4) {
                SegmentedToggle(
                    selection: $selection,
                    options: [
                        .init(value: "default",   label: "Default",   tint: ManifoldPalette.claude, systemImage: "folder"),
                        .init(value: "session",   label: "Session",   tint: ManifoldPalette.active, systemImage: "play.fill"),
                        .init(value: "attention", label: "Watch",     tint: ManifoldPalette.attention, systemImage: "eye"),
                    ]
                )
                Text("Selection: \(selection)")
                    .font(ManifoldType.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.s6)
            .frame(width: 420)
            .background(ManifoldPalette.bg)
        }
    }
    return Demo()
}
