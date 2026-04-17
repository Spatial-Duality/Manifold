// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// EmptyStateIllustration — glowing card + icon composite.
//
// Used by every "nothing is here yet" surface (empty Access, empty Mail,
// empty Requests). Gentle not celebratory — an empty state in a trust
// product is the default state, and should feel calm.

import SwiftUI

struct EmptyStateIllustration: View {
    enum Style {
        case generic
        case activity
        case access
        case mail
        case requests
    }

    let systemImage: String
    let title: String
    var subtitle: String?
    var tint: Color = ManifoldPalette.claude
    var style: Style = .generic

    var body: some View {
        VStack(spacing: Spacing.s4) {
            illustration
            .frame(height: 120)

            VStack(spacing: Spacing.s1) {
                Text(title)
                    .font(ManifoldType.heading)
                    .foregroundStyle(ManifoldPalette.text)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(ManifoldType.body)
                        .foregroundStyle(ManifoldPalette.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 360)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle ?? "")")
    }

    @ViewBuilder
    private var illustration: some View {
        switch style {
        case .activity:
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.09))
                    .frame(width: 132, height: 92)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach([18.0, 26.0, 14.0, 34.0, 22.0, 30.0], id: \.self) { value in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint.opacity(0.28))
                            .frame(width: 12, height: value)
                    }
                }
                .offset(y: 8)
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(tint)
                    .offset(y: -22)
            }
        case .access:
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.09))
                    .frame(width: 132, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(tint.opacity(0.28))
                                .frame(width: index == 0 ? 18 : 12, height: 10)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.18))
                                .frame(width: index == 0 ? 70 : 58, height: 8)
                        }
                        .padding(.leading, CGFloat(index) * 10)
                    }
                }
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(tint)
                    .offset(x: -42, y: -22)
            }
        case .mail:
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.09))
                    .frame(width: 132, height: 92)
                VStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.3))
                                .frame(width: 12, height: 12)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.18))
                                .frame(width: 26, height: 8)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.22))
                                .frame(width: 42, height: 8)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.16))
                                .frame(width: 24, height: 8)
                        }
                    }
                }
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(tint)
                    .offset(y: -24)
            }
        case .requests:
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.09))
                    .frame(width: 132, height: 92)
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(index == 0 ? 0.28 : 0.18))
                            .frame(width: 78 + CGFloat(index * 10), height: 16)
                    }
                }
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(tint)
                    .offset(y: -24)
            }
        case .generic:
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 92, height: 92)
                    .blur(radius: 24)
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(tint)
            }
        }
    }
}

#Preview("Empty state — folders") {
    EmptyStateIllustration(
        systemImage: "folder.badge.plus",
        title: "No folders shared yet",
        subtitle: "Nothing is shared until you share it. Add a folder to let Claude or Codex read it inside a session."
    )
    .frame(width: 520, height: 360)
    .background(ManifoldPalette.bg)
}

#Preview("Empty state — requests") {
    EmptyStateIllustration(
        systemImage: "checkmark.seal",
        title: "Nothing is waiting on you",
        subtitle: "When an agent asks for standing write access through Manifold it lands here. Requests get answered in a ladder — not this time, once, or add to default.",
        tint: ManifoldPalette.active
    )
    .frame(width: 520, height: 360)
    .background(ManifoldPalette.bg)
}
