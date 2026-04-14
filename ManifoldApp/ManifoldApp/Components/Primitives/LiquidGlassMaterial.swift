// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// LiquidGlassMaterial — chrome-only translucent surface.
//
// Wraps `NSVisualEffectView` with an inner highlight stroke and a tinted
// translucent fill, producing the depth the menu bar panel and inspector
// popovers need. Use ONLY on navigation chrome (Principle 10: glass is
// the navigation layer; content never uses glass).
//
// For macOS 26+, prefers `.glassEffect` via `glassBackground(in:)` in
// Spacing.swift. This file is the NSVisualEffectView fallback and the
// place we get to control the inner highlight for older OSes and previews.

import SwiftUI
import AppKit

/// Background modifier producing a glass-like surface with a subtle inner
/// highlight and a hairline border, clipped to a rounded-rectangle shape.
struct LiquidGlassBackground: ViewModifier {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    let cornerRadius: CGFloat

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blending: NSVisualEffectView.BlendingMode = .behindWindow,
        cornerRadius: CGFloat = Spacing.r6
    ) {
        self.material = material
        self.blending = blending
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                ZStack {
                    VisualEffectView(material: material, blending: blending)
                    shape
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        .blendMode(.plusLighter)
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(ManifoldPalette.border, lineWidth: 0.5)
            )
    }
}

extension View {
    /// Apply a chrome-level liquid glass surface. Do not use on content cards.
    func liquidGlass(
        cornerRadius: CGFloat = Spacing.r6,
        material: NSVisualEffectView.Material = .hudWindow
    ) -> some View {
        modifier(LiquidGlassBackground(
            material: material,
            cornerRadius: cornerRadius
        ))
    }
}

/// NSVisualEffectView bridged to SwiftUI. Kept private to this file to
/// discourage ad-hoc use outside the chrome primitives.
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

#Preview("Liquid Glass — chrome surface") {
    ZStack {
        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        VStack(spacing: Spacing.s3) {
            Text("Menu bar panel")
                .font(ManifoldType.heading)
            Text("Chrome uses LiquidGlass; content stays on calm surfaces.")
                .font(ManifoldType.body)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.s5)
        .frame(width: 360)
        .liquidGlass(cornerRadius: Spacing.r6)
        .panelElevation()
    }
    .frame(width: 520, height: 320)
}
