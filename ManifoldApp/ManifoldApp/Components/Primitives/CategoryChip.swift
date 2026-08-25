// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// CategoryChip — labeled chip for a PrivacyCategory.
//
// The chip reads as pure identity: category glyph + name, tinted in the
// palette slot reserved for that category. Used in privacy findings
// summaries, approval previews, rule matcher summaries, and activity rows.

import SwiftUI
import ManifoldKit

struct CategoryChip: View {
    let category: PrivacyCategory
    var compact: Bool = false

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Image(systemName: Self.systemImage(for: category))
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            if !compact {
                Text(category.displayName)
                    .font(ManifoldType.tiny)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
        }
        .padding(.horizontal, compact ? Spacing.s1 : Spacing.s2)
        .padding(.vertical, 2)
        .foregroundStyle(Self.color(for: category))
        .background(
            Capsule(style: .continuous)
                .fill(Self.color(for: category).opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Self.color(for: category).opacity(0.22), lineWidth: 0.5)
        )
        .accessibilityLabel(category.displayName)
    }

    static func color(for category: PrivacyCategory) -> Color {
        // No agent-identity colors here: a chip in Claude orange or
        // Codex blue reads as "this agent touched it", and those hues
        // are reserved (DesignTokens Principle 6). The glyph carries
        // identity; color is a redundant channel, so shared hues are
        // fine.
        switch category {
        case .secret:         return ManifoldPalette.danger
        case .accountNumber:  return ManifoldPalette.attention
        case .privatePerson:  return ManifoldPalette.paused
        case .email:          return ManifoldPalette.selection
        case .phone:          return ManifoldPalette.selection
        case .address:        return ManifoldPalette.preview
        case .url:            return ManifoldPalette.text2
        case .date:           return ManifoldPalette.text3
        }
    }

    static func systemImage(for category: PrivacyCategory) -> String {
        switch category {
        case .secret:         return "lock.shield"
        case .accountNumber:  return "creditcard"
        case .privatePerson:  return "person.crop.circle"
        case .email:          return "envelope"
        case .phone:          return "phone"
        case .address:        return "mappin.and.ellipse"
        case .url:            return "link"
        case .date:           return "calendar"
        }
    }
}

#Preview("CategoryChip") {
    VStack(alignment: .leading, spacing: Spacing.s2) {
        HStack(spacing: Spacing.s1) {
            ForEach(PrivacyCategory.allCases, id: \.self) { category in
                CategoryChip(category: category, compact: true)
            }
        }
        HStack(spacing: Spacing.s1) {
            ForEach(PrivacyCategory.allCases, id: \.self) { category in
                CategoryChip(category: category)
            }
        }
    }
    .padding(Spacing.s5)
    .background(ManifoldPalette.bg)
}
