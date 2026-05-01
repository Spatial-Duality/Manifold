// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// DesignTokens — Manifold's source of truth for color, type, motion, elevation.
//
// Per design/02-posture-and-principles.md §6 (color-as-identity and
// color-as-state on separate channels) and design/html/tokens.css, Manifold
// uses a fixed palette that is NOT tied to the user's system accent.
//
// Legacy names (Color.claudeBlue, .statusActive, Typ.caption, Anim.micro, …)
// are preserved so existing views continue to compile while Phase 1 ships.
// New code should prefer ManifoldPalette / ManifoldType / ManifoldMotion /
// ManifoldElevation — the names match the token layer.

import SwiftUI
import ManifoldKit

// MARK: - ManifoldPalette (canonical, scheme-aware)
//
// Values mirror design/html/tokens.css. Light and dark variants are
// hand-picked (Principle 6) so each agent reads the same in peripheral
// vision across every macOS accent setting.

enum ManifoldPalette {

    // Agent identity — fixed, reserved, never tied to system accent
    static let claude       = dynamicColor(light: 0xD97757, dark: 0xE99A7F)
    static let claudeSoft   = dynamicColor(light: 0xD97757, lightAlpha: 0.10,
                                           dark: 0xE99A7F,  darkAlpha: 0.16)
    static let claudeSoft2  = dynamicColor(light: 0xD97757, lightAlpha: 0.18,
                                           dark: 0xE99A7F,  darkAlpha: 0.26)

    static let codex        = dynamicColor(light: 0x5C7FF7, dark: 0x9EACFE)
    static let codexSoft    = dynamicColor(light: 0x5C7FF7, lightAlpha: 0.10,
                                           dark: 0x9EACFE,  darkAlpha: 0.16)
    static let codexSoft2   = dynamicColor(light: 0x5C7FF7, lightAlpha: 0.18,
                                           dark: 0x9EACFE,  darkAlpha: 0.26)

    // Product chrome / selection — neutral, never agent-coded
    static let selection    = dynamicColor(light: 0x51627D, dark: 0xA6B1C2)
    static let selectionSoft = dynamicColor(light: 0x51627D, lightAlpha: 0.12,
                                            dark: 0xA6B1C2, darkAlpha: 0.18)
    static let preview      = dynamicColor(light: 0xA36A12, dark: 0xD79B40)
    static let previewSoft  = dynamicColor(light: 0xA36A12, lightAlpha: 0.12,
                                           dark: 0xD79B40, darkAlpha: 0.18)

    // Status — always reinforced by a second channel (icon/text)
    static let active       = dynamicColor(light: 0x1FAB5A, dark: 0x30C060)
    static let activeSoft   = dynamicColor(light: 0x1FAB5A, lightAlpha: 0.10,
                                           dark: 0x30C060,  darkAlpha: 0.15)

    static let paused       = dynamicColor(light: 0xC8860B, dark: 0xE0A030)
    static let pausedSoft   = dynamicColor(light: 0xC8860B, lightAlpha: 0.10,
                                           dark: 0xE0A030,  darkAlpha: 0.15)

    static let attention    = dynamicColor(light: 0xD45E00, dark: 0xFF8038)
    static let attentionSoft = dynamicColor(light: 0xD45E00, lightAlpha: 0.10,
                                            dark: 0xFF8038,  darkAlpha: 0.15)

    static let danger       = dynamicColor(light: 0xC8201E, dark: 0xE05450)
    static let dangerSoft   = dynamicColor(light: 0xC8201E, lightAlpha: 0.10,
                                           dark: 0xE05450,  darkAlpha: 0.15)

    // Brand identity — Manifold's signature accent.
    //
    // Saffron yellow, in the same family as Apple Ideas. Lives in its own
    // channel separate from agent identity (claude/codex) and state colours
    // (active/preview/attention/danger). Used SPARSELY: app icon, splash
    // settle, hero atmosphere, hover-tinted Liquid Glass, single CTAs.
    // Never used as a session-state colour — that's what `active` etc. are
    // for.
    //
    // The 1.7:1 contrast against white is intentional — `brand` is a
    // FILL colour, not a TEXT colour. Foreground content sits in `text`
    // (warm-charcoal) on top of the saffron, which gives 11:1 contrast.
    static let brand        = dynamicColor(light: 0xF5B400, dark: 0xFFC940)
    static let brandSoft    = dynamicColor(light: 0xF5B400, lightAlpha: 0.10,
                                           dark: 0xFFC940,  darkAlpha: 0.16)
    static let brandSoft2   = dynamicColor(light: 0xF5B400, lightAlpha: 0.18,
                                           dark: 0xFFC940,  darkAlpha: 0.26)
    /// Lighter highlight for atmospheric mesh gradients — "sun catching the cloud".
    static let brandLift    = dynamicColor(light: 0xFFD755, dark: 0xFFE08A)
    /// Deeper shadow for atmospheric mesh gradients — "the side of the cloud
    /// the light isn't hitting".
    static let brandDeep    = dynamicColor(light: 0xD99800, dark: 0xC89030)

    // Surfaces — used by chrome, inspectors, ledger rows
    static let bg           = dynamicColor(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let surface      = dynamicColor(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let surface2     = dynamicColor(light: 0xFBFBFD, dark: 0x242426)
    static let surface3     = dynamicColor(light: 0xF0F0F2, dark: 0x343438)
    static let surface4     = dynamicColor(light: 0xE8E8EA, dark: 0x3A3A3C)

    static let border       = dynamicColor(light: 0x000000, lightAlpha: 0.08,
                                           dark: 0xFFFFFF,  darkAlpha: 0.08)
    static let border2      = dynamicColor(light: 0x000000, lightAlpha: 0.14,
                                           dark: 0xFFFFFF,  darkAlpha: 0.14)

    // Text — four tiers
    static let text         = dynamicColor(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let text2        = dynamicColor(light: 0x55555A, dark: 0xC5C5C8)
    static let text3        = dynamicColor(light: 0x8A8A8E, dark: 0x8A8A8E)
    static let text4        = dynamicColor(light: 0xB5B5B9, dark: 0x5A5A5E)

    // Agent accessor
    static func agent(_ agent: TargetApp) -> Color {
        agent == .codex ? codex : claude
    }

    static func agentSoft(_ agent: TargetApp) -> Color {
        agent == .codex ? codexSoft : claudeSoft
    }
}

// MARK: - AgentMeta
//
// Central display metadata for every agent identity the UI can render.
// UI code must read label / color / systemImage from here instead of
// hardcoding Claude / Codex strings. When the agent registry becomes
// data-driven, only this helper needs to change.

enum AgentMeta {
    /// Short human-readable label used in chips, segmented controls, menus.
    static func label(_ agent: TargetApp) -> String {
        switch agent {
        case .codex:  return "Codex"
        case .cowork: return "Claude"
        }
    }

    /// Fixed identity color for this agent.
    static func color(_ agent: TargetApp) -> Color {
        ManifoldPalette.agent(agent)
    }

    /// SF Symbol representing this agent.
    static func systemImage(_ agent: TargetApp) -> String {
        switch agent {
        case .codex:  return "chevron.left.forwardslash.chevron.right"
        case .cowork: return "sparkle"
        }
    }

    /// Asset-catalog image for the agent's product mark.
    static func logoImageName(_ agent: TargetApp, colorScheme: ColorScheme) -> String {
        switch agent {
        case .codex:
            return colorScheme == .dark ? "AgentCodexDark" : "AgentCodexLight"
        case .cowork:
            return "AgentClaude"
        }
    }

    /// Best-effort conversion of a connected-agent raw string into a known
    /// `TargetApp`. Unknown identifiers silently drop out; the UI should
    /// show nothing rather than a mislabeled placeholder.
    static func resolve(_ raw: String) -> TargetApp? {
        TargetApp(rawValue: raw)
    }

    /// Ordered agent list for access controls. Connection is metadata, not
    /// permission to configure policy, so Claude/Codex remain available while
    /// offline.
    static func connected(from raw: [String]) -> [TargetApp] {
        let connected = raw.compactMap(resolve)
        return TargetApp.allCases.sorted { lhs, rhs in
            let lhsConnected = connected.contains(lhs)
            let rhsConnected = connected.contains(rhs)
            if lhsConnected != rhsConnected { return lhsConnected && !rhsConnected }
            return order(lhs) < order(rhs)
        }
    }

    /// Stable key for a list of agents. Drives `.task(id:)` so views
    /// reload data when the connected-agent set changes.
    static func stableKey(_ agents: [TargetApp]) -> String {
        agents.map(\.rawValue).sorted().joined(separator: ",")
    }

    private static func order(_ agent: TargetApp) -> Int {
        switch agent {
        case .cowork: return 0
        case .codex: return 1
        }
    }
}

// MARK: - Dynamic Color helper
//
// Builds a scheme-aware SwiftUI `Color` from a light and dark hex pair,
// respecting accessibility high-contrast appearances. Use this rather than
// `Color(.sRGB, …)` so the palette snaps to dark mode without a second
// definition.

private func dynamicColor(
    light: UInt32,
    lightAlpha: Double = 1.0,
    dark: UInt32,
    darkAlpha: Double = 1.0
) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        switch appearance.name {
        case .darkAqua,
             .vibrantDark,
             .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantDark:
            return NSColor(hex: dark, alpha: darkAlpha)
        default:
            return NSColor(hex: light, alpha: lightAlpha)
        }
    })
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((hex >>  8) & 0xFF) / 255.0,
            blue:    CGFloat( hex        & 0xFF) / 255.0,
            alpha:   CGFloat(alpha)
        )
    }
}

// MARK: - Legacy semantic color names (kept for back-compat)
//
// Existing views import `Color.claudeBlue` etc. We preserve the names but
// route them through the fixed palette so the whole app picks up Principle 6
// immediately — no more `.blue` / `.purple` following system accent.

extension Color {
    /// Claude identity. Fixed, not system accent.
    static let claudeBlue: Color = ManifoldPalette.claude
    /// Codex identity. Fixed, not system accent.
    static let codexPurple: Color = ManifoldPalette.codex

    /// Status: agent active, session live, tracked-edit healthy.
    static let statusActive: Color = ManifoldPalette.active
    /// Status: paused by user.
    static let statusPaused: Color = ManifoldPalette.paused
    /// Status: soft warning (kept for legacy).
    static let statusWarning: Color = ManifoldPalette.paused
    /// Status: denial, pending queue badge, attention-worthy.
    static let statusAttention: Color = ManifoldPalette.attention
    /// Status: error that prevents the product from working.
    static let statusDanger: Color = ManifoldPalette.danger

    /// Fixed agent color by `TargetApp`.
    static func agent(_ agent: ManifoldKit.TargetApp) -> Color {
        ManifoldPalette.agent(agent)
    }
}

// MARK: - Typography

/// Named type roles — use these everywhere instead of ad-hoc `.font()` calls.
/// Sizes track `tokens.css` so Swift and mockups stay aligned.
enum Typ {
    /// 10/14 uppercase — kickers, stage tags, section labels in dense UI.
    static let tiny: Font           = .system(size: 10, weight: .medium)
    /// 11/16 — timestamps, counts, micro meta.
    static let caption: Font        = .caption
    static let captionMedium: Font  = .caption.weight(.medium)
    /// 13/20 — primary body text.
    static let body: Font           = .callout
    static let bodyMedium: Font     = .callout.weight(.medium)
    /// 14/20 — section titles in tight space (toolbars, inspectors).
    static let title: Font          = .system(size: 14, weight: .semibold)
    /// 17/24 — window / inspector heading.
    static let heading: Font        = .system(size: 17, weight: .semibold)
    /// 22/28 — display type for first-run and big empty states.
    static let display: Font        = .system(size: 22, weight: .semibold)
    /// Wordmark — the "Manifold" name itself. One single use site
    /// (sidebar brand header) so it reads as identity, not as a heading.
    /// Light weight + slightly tighter tracking sets it apart from any
    /// other label in the app.
    static let wordmark: Font       = .system(size: 16, weight: .light)

    /// Section title legacy alias (used by Settings, etc).
    static let sectionTitle: Font   = .title3.weight(.semibold)
    /// Mono body — file paths, code, version hashes.
    static let mono: Font           = .caption.monospaced()
    /// Mono primary body.
    static let monoBody: Font       = .system(size: 12, weight: .regular, design: .monospaced)
    /// Numeric body — counts, byte sizes.
    static let numericBody: Font    = .callout.monospacedDigit()
    /// Numeric caption — counts in badges, timestamps.
    static let numericCaption: Font = .caption.monospacedDigit()
}

/// Canonical new-world alias — prefer `ManifoldType` in new code.
enum ManifoldType {
    static let tiny           = Typ.tiny
    static let caption        = Typ.caption
    static let captionMedium  = Typ.captionMedium
    static let body           = Typ.body
    static let bodyMedium     = Typ.bodyMedium
    static let title          = Typ.title
    static let heading        = Typ.heading
    static let display        = Typ.display
    static let wordmark       = Typ.wordmark
    static let mono           = Typ.mono
    static let monoBody       = Typ.monoBody
    static let numericBody    = Typ.numericBody
    static let numericCaption = Typ.numericCaption
}

// MARK: - Opacity scale

enum Opacity {
    static let rowTint: Double = 0.04
    static let badgeFill: Double = 0.12
    static let hoverHighlight: Double = 0.06
    static let disabled: Double = 0.5
    static let scrim: Double = 0.3
}

// MARK: - Elevation (shadows)

extension View {
    /// Low-elevation card (rows, chips, inline cards).
    func cardElevation() -> some View {
        shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
    /// Card on hover.
    func cardHoverElevation() -> some View {
        shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
    /// Popover (menu bar panel, dropdowns).
    func popoverElevation() -> some View {
        shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }
    /// Sheet / inspector panel.
    func panelElevation() -> some View {
        shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }
    /// Toast notification.
    func toastElevation() -> some View {
        shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}

// MARK: - Motion

/// Motion grammar.
///
/// Every animation in Manifold goes through one of these presets so the
/// motion language stays coherent and reduce-motion can dampen them
/// centrally. The grammar:
///
/// - `micro`   — 150ms ease-out. Hover-in, hover-out, focus ring, tooltip
///   reveal. Anything where the user wants the response immediately.
/// - `state`   — 200ms ease-out. Status color change, badge swap,
///   selection highlight. State communication where the eye should
///   register the change but not be drawn to it.
/// - `landing` — 300ms ease-out. Entrance of a new surface (sheet body
///   appearing, panel transition, content swap). Lands deliberately.
/// - `spring`  — 0.32s response, 0.82 damping. Structural movement
///   (column resize, sheet present, drawer open). Inertia carries the
///   eye to the new position.
/// - `pulseEaseOut` — 2s ease-out repeating. Reserved for "needs
///   attention" affordances and brand moments. Use sparingly: pulsing
///   reads as "do something" in macOS.
///
/// **Don't add a new constant for a one-off duration.** If you find
/// yourself reaching for `.easeInOut(duration: 0.42)` inline, the
/// motion either belongs in this grammar or doesn't belong at all.
enum ManifoldMotion {
    static let micro:      Animation = .easeOut(duration: 0.15)
    static let state:      Animation = .easeOut(duration: 0.20)
    static let landing:    Animation = .easeOut(duration: 0.30)
    static let spring:     Animation = .spring(response: 0.32, dampingFraction: 0.82)
    static let pulseEaseOut: Animation = .easeOut(duration: 2.0).repeatForever(autoreverses: false)

    /// Use in views that already consume `@Environment(\.accessibilityReduceMotion)`
    /// to guarantee the requested animation collapses under reduce-motion.
    static func effective(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Legacy alias — existing call sites use `Anim.micro`, `.stateChange`, etc.
enum Anim {
    static let stateChange: Animation = ManifoldMotion.state
    static let structural:  Animation = ManifoldMotion.spring
    static let entrance:    Animation = ManifoldMotion.landing
    static let micro:       Animation = ManifoldMotion.micro

    static func effective(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .default : animation
    }
}

// MARK: - Path utilities

extension String {
    /// Shorten an absolute path by replacing the home directory with `~`.
    var shortenedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
