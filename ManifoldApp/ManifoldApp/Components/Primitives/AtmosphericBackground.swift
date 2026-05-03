// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AtmosphericBackground — Manifold's hero / splash background.
//
// Layers (bottom to top):
//   1. Saffron base — `ManifoldPalette.accent` flat fill.
//   2. MeshGradient with slow-drifting interior points — adds organic
//      colour blending; "breathing" via two incommensurate cycles
//      (23s and 31s) so the field never visibly repeats.
//   3. (Tier 3, deferred) Metal cloud shader — domain-warped fbm.
//   4. (Tier 3, deferred) Metal grain shader — fractal noise overlay.
//   5. Optional foreground content via @ViewBuilder.
//
// The breathing interior of the mesh is small (±0.04 in normalised
// coordinates) so the motion is barely perceptible — it's the *cumulative*
// effect over 30 seconds that reads as "alive but calm." Reduce-motion
// collapses both cycles to their midpoints (static).
//
// Used in: TitleSequence settle and FirstRun ConceptPanel.

import SwiftUI

struct AtmosphericBackground<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content
    /// When `true`, only the breathing mesh layer is drawn (skip the
    /// Metal cloud + grain pass). Useful for very small surfaces where
    /// the shader cost wouldn't pay off.
    var meshOnly: Bool = false

    init(meshOnly: Bool = false, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.meshOnly = meshOnly
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Layer 1+2: breathing mesh gradient (runs always).
            BreathingMeshLayer(reduceMotion: reduceMotion)
                .ignoresSafeArea()

            // Layer 3+4: Metal cloud + grain (skip on reduce-motion / meshOnly).
            // The shaders apply as colorEffects, multiplying against the
            // mesh underneath — they enhance but don't replace it.
            if !meshOnly {
                Color.clear
                    .ignoresSafeArea()
                    .modifier(AtmosphericShaderStack(reduceMotion: reduceMotion))
                    .allowsHitTesting(false)
            }

            content
        }
    }
}

// MARK: - Layer 3+4: Metal cloud + grain

/// Stacks the cloud shader (animated, gamma-correct, curl-displaced fbm)
/// and the grain shader (static, fine fractal noise) on top of the mesh
/// gradient. The cloud shader skips its time-driven sampling under
/// reduce-motion so the field freezes; the grain shader is static
/// regardless.
private struct AtmosphericShaderStack: ViewModifier {
    let reduceMotion: Bool
    private let startDate = Date()

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: reduceMotion)) { context in
            let elapsed = reduceMotion
                ? 0
                : context.date.timeIntervalSince(startDate)

            content
                .visualEffect { view, proxy in
                    view
                        .colorEffect(
                            ShaderLibrary.manifoldCloud(
                                .float2(proxy.size),
                                .float(Float(elapsed))
                            )
                        )
                        .colorEffect(
                            ShaderLibrary.manifoldGrain(
                                .float2(proxy.size),
                                .float(0.5)
                            )
                        )
                }
        }
    }
}

// MARK: - Layer 2: Breathing mesh gradient

private struct BreathingMeshLayer: View {
    let reduceMotion: Bool
    private let startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let elapsed = reduceMotion
                ? 0
                : context.date.timeIntervalSince(startDate)

            // Two slow incommensurate cycles. Tuned so the field never
            // repeats within a session — every viewing is slightly different.
            // 23s and 31s are coprime; their LCM is 713 seconds (~12 min).
            let t1 = Float(sin(elapsed / 23.0 * .pi)) * 0.04
            let t2 = Float(cos(elapsed / 31.0 * .pi)) * 0.04

            MeshGradient(
                width: 5,
                height: 5,
                points: meshPoints(t1: t1, t2: t2),
                colors: meshColors,
                background: ManifoldPalette.accent
            )
            .ignoresSafeArea()
        }
    }

    /// 5×5 mesh point grid. Outer 16 points are anchored to the canvas edge
    /// so the gradient always fills the frame; the interior 9 points drift
    /// on the breathing cycles.
    private func meshPoints(t1: Float, t2: Float) -> [SIMD2<Float>] {
        [
            // Row 0 (top, anchored)
            SIMD2(0.00, 0.00), SIMD2(0.25, 0.00), SIMD2(0.50, 0.00), SIMD2(0.75, 0.00), SIMD2(1.00, 0.00),

            // Row 1 — interior drifts
            SIMD2(0.00, 0.25),
            SIMD2(0.25 + t1, 0.25 - t2),
            SIMD2(0.50 - t2, 0.25 + t1),
            SIMD2(0.75 - t1, 0.25 - t2),
            SIMD2(1.00, 0.25),

            // Row 2 — middle, biggest drift
            SIMD2(0.00, 0.50),
            SIMD2(0.25 - t2, 0.50 + t1),
            SIMD2(0.50 + t1, 0.50 - t2),
            SIMD2(0.75 + t2, 0.50 + t1),
            SIMD2(1.00, 0.50),

            // Row 3 — interior drifts
            SIMD2(0.00, 0.75),
            SIMD2(0.25 + t2, 0.75 + t1),
            SIMD2(0.50 - t1, 0.75 + t2),
            SIMD2(0.75 + t1, 0.75 - t2),
            SIMD2(1.00, 0.75),

            // Row 4 (bottom, anchored)
            SIMD2(0.00, 1.00), SIMD2(0.25, 1.00), SIMD2(0.50, 1.00), SIMD2(0.75, 1.00), SIMD2(1.00, 1.00),
        ]
    }

    /// 25 colours, one per mesh point. The pattern alternates between
    /// the saffron lift (highlight) and the saffron deep (shadow), with
    /// the saffron accent in between. The result reads as cloud-and-light
    /// rather than a single hue.
    private var meshColors: [Color] {
        let lift = ManifoldPalette.accentLift   // sun catches the cloud
        let mid  = ManifoldPalette.accent        // saffron base
        let deep = ManifoldPalette.accentDeep   // shadow side
        return [
            // Row 0 — top edge (deeper, like the sky's far edge)
            deep, deep, mid,  lift, deep,
            // Row 1
            deep, mid,  lift, mid,  deep,
            // Row 2 — centre row carries the most light
            mid,  lift, mid,  deep, mid,
            // Row 3
            deep, mid,  lift, mid,  deep,
            // Row 4 — bottom edge mirrors top
            deep, deep, mid,  lift, deep,
        ]
    }
}

// MARK: - Previews

#Preview("Atmospheric — empty") {
    AtmosphericBackground()
        .frame(width: 600, height: 400)
}

#Preview("Atmospheric — with content") {
    AtmosphericBackground {
        VStack(spacing: 24) {
            ManifoldMark(placement: .display, color: ManifoldPalette.text)
                .frame(width: 120, height: 120)
            Text("MANIFOLD")
                .font(.system(size: 32, weight: .medium))
                .tracking(0.16 * 32)
                .foregroundStyle(ManifoldPalette.text)
            Text("ACCESS, RECORDED.")
                .font(.system(size: 11, weight: .light))
                .tracking(0.32 * 11)
                .foregroundStyle(ManifoldPalette.text.opacity(0.65))
        }
    }
    .frame(width: 800, height: 480)
}
