// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// AgentStatusDot — the atom for "is this agent alive right now".
//
// Draws a small filled circle tinted for the status, optionally overlaid
// with a pulsing halo when the status is `.active`. Reduce-motion is
// honored: halos collapse to a static inner glow.

import SwiftUI

struct AgentStatusDot: View {
    enum Status {
        case active
        case paused
        case denied
        case offline

        var color: Color {
            switch self {
            case .active:  return ManifoldPalette.active
            case .paused:  return ManifoldPalette.paused
            case .denied:  return ManifoldPalette.attention
            case .offline: return ManifoldPalette.text3
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .active:  return "Active"
            case .paused:  return "Paused"
            case .denied:  return "Denied"
            case .offline: return "Offline"
            }
        }
    }

    let status: Status
    var size: CGFloat = 8
    var pulses: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOn = false

    var body: some View {
        ZStack {
            if status == .active, pulses, !reduceMotion {
                Circle()
                    .fill(status.color.opacity(0.35))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(pulseOn ? 1.0 : 0.55)
                    .opacity(pulseOn ? 0 : 0.9)
                    .animation(ManifoldMotion.pulseEaseOut, value: pulseOn)
                    .onAppear { pulseOn = true }
            } else if status == .active, pulses {
                Circle()
                    .fill(status.color.opacity(0.25))
                    .frame(width: size * 1.6, height: size * 1.6)
            }
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2, height: size * 2)
        .accessibilityLabel(status.accessibilityLabel)
    }
}

#Preview("Status dots") {
    HStack(spacing: Spacing.s6) {
        VStack { AgentStatusDot(status: .active);  Text("active").font(ManifoldType.tiny) }
        VStack { AgentStatusDot(status: .paused);  Text("paused").font(ManifoldType.tiny) }
        VStack { AgentStatusDot(status: .denied);  Text("denied").font(ManifoldType.tiny) }
        VStack { AgentStatusDot(status: .offline); Text("offline").font(ManifoldType.tiny) }
    }
    .padding(Spacing.s6)
    .background(ManifoldPalette.bg)
}
