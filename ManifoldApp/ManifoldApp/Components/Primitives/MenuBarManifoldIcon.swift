// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// MenuBarManifoldIcon — the Manifold mark with state badge, rendered for the
// macOS menu bar.
//
// MenuBarExtra requires AppKit-rendered NSImage to size correctly at 18pt;
// SwiftUI's resizing modifiers are silently ignored when the label is a
// non-system image. We render the ManifoldMark + badge through ImageRenderer
// and hand the resulting NSImage to MenuBarExtra as a template image, so
// the system handles dark-mode and selection inversion natively.
//
// Reduce-motion is respected: `breathe` only plays when the runtime has
// something for the user (pending approvals).

import SwiftUI
import AppKit

enum MenuBarBadgeState: Equatable {
    /// Runtime connected, nothing demanding attention. Plain mark, no badge.
    case clear
    /// Approvals waiting on the user. Mark breathes, attention badge pinned.
    case approvalsPending
    /// Every connected agent paused. Static paused badge.
    case paused
    /// XPC unreachable. Static danger badge — the most important thing the
    /// menu bar communicates.
    case disconnected

    var badgeSymbol: String? {
        switch self {
        case .clear:            return nil
        case .approvalsPending: return "hand.raised.fill"
        case .paused:           return "pause.circle.fill"
        case .disconnected:     return "exclamationmark.triangle.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .clear:            return .clear
        case .approvalsPending: return ManifoldPalette.attention
        case .paused:           return ManifoldPalette.paused
        case .disconnected:     return ManifoldPalette.danger
        }
    }
}

// MARK: - Live (in-app, animated) version

/// Used only inside the app's process for previews and verification —
/// MenuBarExtra itself receives a static rendered NSImage.
struct MenuBarManifoldIcon: View {
    let state: MenuBarBadgeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            mark
                .modifier(BreatheIfApprovals(active: state == .approvalsPending && !reduceMotion))
            if let symbol = state.badgeSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(state.badgeColor)
                    .frame(width: 8, height: 8)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var mark: some View {
        ManifoldMark(placement: .menubar, color: ManifoldPalette.text)
            .frame(width: 16, height: 16)
    }
}

private struct BreatheIfApprovals: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            // Hand-rolled breathe: 1.0 → 0.86 opacity over 1.6s, repeating.
            // Apple's `.symbolEffect(.breathe)` applies only to SF Symbols;
            // we apply the same character to a custom Canvas mark.
            content
                .modifier(BreatheTimeline())
        } else {
            content
        }
    }
}

private struct BreatheTimeline: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            // 1.6s breathe cycle — slower than a heartbeat, faster than
            // an idle pulse. Tuned to read as "waiting" not "alarmed."
            let phase = context.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 1.6)
            let unit  = (sin((phase / 1.6) * 2 * .pi) + 1) / 2  // 0…1
            let opacity = 0.86 + (1.0 - 0.86) * unit
            content.opacity(opacity)
        }
    }
}

// MARK: - Static rendering for MenuBarExtra label

extension MenuBarManifoldIcon {
    /// Render a non-animated frame of the icon for MenuBarExtra. The system
    /// menu bar takes a single NSImage at a time; for the breathe pulse to
    /// be visible we'd need to swap the image periodically. We deliberately
    /// trade the in-menubar pulse for a stable template image — the real
    /// pulse signal lives inside the panel, where it's more readable.
    @MainActor
    static func renderTemplateImage(state: MenuBarBadgeState) -> NSImage? {
        let view = StaticMenuBarManifoldIcon(state: state)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 18, height: 18))
        // Template mode: macOS handles tinting for menu bar appearance and
        // when the menu is opened. Without this, the icon would stay the
        // same color regardless of menu bar transparency or selection.
        image.isTemplate = (state == .clear)
        // Non-clear states have a colored badge that should NOT be
        // template-tinted by the system — we keep them as-is.
        return image
    }
}

private struct StaticMenuBarManifoldIcon: View {
    let state: MenuBarBadgeState

    var body: some View {
        ZStack {
            ManifoldMark(placement: .menubar, color: ManifoldPalette.text)
                .frame(width: 16, height: 16)
            if let symbol = state.badgeSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(state.badgeColor)
                    .frame(width: 8, height: 8)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

#Preview("Menu bar icon — all states") {
    HStack(spacing: 16) {
        VStack { MenuBarManifoldIcon(state: .clear);            Text(".clear").font(ManifoldType.tiny) }
        VStack { MenuBarManifoldIcon(state: .approvalsPending); Text(".approvalsPending").font(ManifoldType.tiny) }
        VStack { MenuBarManifoldIcon(state: .paused);           Text(".paused").font(ManifoldType.tiny) }
        VStack { MenuBarManifoldIcon(state: .disconnected);     Text(".disconnected").font(ManifoldType.tiny) }
    }
    .padding(24)
    .background(ManifoldPalette.bg)
}
