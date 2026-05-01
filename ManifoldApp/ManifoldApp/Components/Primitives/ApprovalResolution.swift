// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ApprovalResolution — the one branded confirmation animation in Manifold.
//
// When the user resolves an approval (deny / allow once / add to default),
// the row animates locally before the store removes it from
// `pendingRequests`. Two-stage:
//
//   0–180ms   tiny lift (1.0 → 1.03 scale, opacity 1.0)
//   180–500ms settle out (1.03 → 0.97, opacity 1.0 → 0)
//
// The user feels the resolution land before the row vanishes. No
// branded-mark pop, no checkmark dance — just the row breathing once
// and disappearing. Sparing.
//
// Reduce-motion bypass: the modifier collapses to a pure 200ms opacity
// fade, which the system reads as "respectful" rather than disabled.

import SwiftUI

struct ApprovalResolutionValues: Animatable {
    var scale: CGFloat = 1.0
    var opacity: CGFloat = 1.0
    var blur: CGFloat = 0.0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(scale, AnimatablePair(opacity, blur)) }
        set {
            scale = newValue.first
            opacity = newValue.second.first
            blur = newValue.second.second
        }
    }
}

struct ApprovalResolutionModifier: ViewModifier {
    /// Bumped once per click; KeyframeAnimator restarts on each change.
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(trigger == 0 ? 1.0 : 0.0)
                .animation(.linear(duration: 0.20), value: trigger)
        } else {
            content
                .keyframeAnimator(
                    initialValue: ApprovalResolutionValues(),
                    trigger: trigger
                ) { content, value in
                    content
                        .scaleEffect(value.scale)
                        .opacity(value.opacity)
                        .blur(radius: value.blur)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.03, duration: 0.18, spring: .smooth)
                        CubicKeyframe(0.97, duration: 0.32)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1.0, duration: 0.18)
                        CubicKeyframe(0.0, duration: 0.32)
                    }
                    KeyframeTrack(\.blur) {
                        LinearKeyframe(0, duration: 0.20)
                        CubicKeyframe(2.0, duration: 0.30)
                    }
                }
        }
    }
}

extension View {
    /// Apply the Manifold approval-resolution animation. The trigger value
    /// should be incremented (or otherwise mutated) when the user resolves
    /// an approval; the modifier replays its keyframe sequence on each
    /// change. Combine with a small delay before the parent removes the
    /// underlying data so the animation has time to complete.
    func approvalResolution(trigger: Int) -> some View {
        modifier(ApprovalResolutionModifier(trigger: trigger))
    }
}

/// Total time the resolution animation needs before the parent should
/// remove the row from its data source. Match this in the dispatch delay.
let approvalResolutionDuration: TimeInterval = 0.50
