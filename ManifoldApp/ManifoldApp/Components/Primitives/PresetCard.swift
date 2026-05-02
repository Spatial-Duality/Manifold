// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PresetCard — tappable tile for the Privacy auto-settings picker.
//
// Four tiles live in a row (Off / Balanced / Strict / Custom). The
// selected tile gets a bold accent border and filled icon; the others
// stay calm. Hover lifts the card with cardHoverElevation to reassure
// the user that a click will actually do something (Principle 1).

import SwiftUI

struct PresetCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let isSelected: Bool
    var accessibilityIdentifier: String?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? accent : accent.opacity(0.14))
                            .frame(width: 28, height: 28)
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : accent)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(title)
                    .font(ManifoldType.bodyMedium)
                    .foregroundStyle(ManifoldPalette.text)
                Text(subtitle)
                    .font(ManifoldType.caption)
                    .foregroundStyle(ManifoldPalette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(Spacing.s3)
            .background(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.08) : ManifoldPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent : ManifoldPalette.border,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Spacing.r4, style: .continuous))
            .animation(ManifoldMotion.effective(ManifoldMotion.state, reduceMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ManifoldMotion.effective(ManifoldMotion.micro, reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .modifier(HoverLift(isHovering: isHovering))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(accessibilityIdentifier ?? "preset.\(title.lowercased())")
    }
}

private struct HoverLift: ViewModifier {
    let isHovering: Bool

    func body(content: Content) -> some View {
        if isHovering {
            content.cardHoverElevation()
        } else {
            content.cardElevation()
        }
    }
}

#Preview("PresetCard") {
    HStack(spacing: Spacing.s3) {
        PresetCard(
            title: "Off",
            subtitle: "No filtering. Agents see content as-is.",
            systemImage: "shield.slash",
            accent: ManifoldPalette.text3,
            isSelected: false,
            accessibilityIdentifier: "preset.off",
            action: {}
        )
        PresetCard(
            title: "Balanced",
            subtitle: "Warn on personal info. Redact secrets.",
            systemImage: "shield.lefthalf.filled",
            accent: ManifoldPalette.selection,
            isSelected: true,
            accessibilityIdentifier: "preset.balanced",
            action: {}
        )
        PresetCard(
            title: "Strict",
            subtitle: "Redact all PII. Block secrets.",
            systemImage: "shield.fill",
            accent: ManifoldPalette.danger,
            isSelected: false,
            accessibilityIdentifier: "preset.strict",
            action: {}
        )
        PresetCard(
            title: "Custom",
            subtitle: "Hand-tune per category and agent.",
            systemImage: "slider.horizontal.3",
            accent: ManifoldPalette.claude,
            isSelected: false,
            accessibilityIdentifier: "preset.custom",
            action: {}
        )
    }
    .padding(Spacing.s5)
    .background(ManifoldPalette.bg)
}
