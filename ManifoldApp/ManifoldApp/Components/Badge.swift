// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// DS-6: Unified badge component replacing all inline capsule/pill patterns.
struct Badge: View {
    enum Variant {
        case info(Color)  // Agent-specific: pass .claudeBlue or .codexPurple
        case success
        case warning
        case danger
        case neutral
    }

    enum Size {
        case compact    // Dot only (6pt), no text
        case standard   // Dot (6pt) + caption text
        case prominent  // Dot (10pt) + body text
    }

    let label: String
    let variant: Variant
    var size: Size = .standard

    var body: some View {
        switch size {
        case .compact:
            Circle()
                .fill(variantColor)
                .frame(width: 6, height: 6)
                .accessibilityLabel(label)

        case .standard:
            HStack(spacing: 4) {
                Circle()
                    .fill(variantColor)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(Typ.caption.weight(.medium))
                    .foregroundStyle(variantColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(variantColor.opacity(Opacity.badgeFill), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)

        case .prominent:
            HStack(spacing: 6) {
                Circle()
                    .fill(variantColor)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(Typ.body)
                    .foregroundStyle(variantColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(variantColor.opacity(Opacity.badgeFill), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
        }
    }

    private var variantColor: Color {
        switch variant {
        case .info(let color): color
        case .success: .statusActive
        case .warning: .statusPaused
        case .danger: .statusDanger
        case .neutral: .secondary
        }
    }
}
