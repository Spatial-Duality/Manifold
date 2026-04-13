// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ManifoldKit

// MARK: - DS-1: Semantic Colors

extension Color {
    /// Agent identity colors — system semantic tokens per DESIGN.md
    static let claudeBlue: Color = .blue
    static let codexPurple: Color = .purple
    static let statusActive: Color = .green
    static let statusPaused: Color = .orange
    static let statusWarning: Color = .yellow
    static let statusDanger: Color = .red

    /// Agent color by type
    static func agent(_ agent: ManifoldKit.TargetApp) -> Color {
        agent == .codex ? .purple : .blue
    }
}

// MARK: - DS-2: Typography Scale

/// Named type roles — use these everywhere instead of ad-hoc .font() calls.
enum Typ {
    /// .title3.weight(.semibold) — Tab headings, card group titles
    static let sectionTitle: Font = .title3.weight(.semibold)
    /// .headline — Card headers, dialog titles, sidebar section headers
    static let heading: Font = .headline
    /// .callout — Primary content text, descriptions
    static let body: Font = .callout
    /// .caption — Timestamps, counts, badge labels, footer text
    static let caption: Font = .caption
    /// .caption.monospaced() — File paths, code, version hashes
    static let mono: Font = .caption.monospaced()
    /// .callout.monospacedDigit() — File counts, byte sizes in body text
    static let numericBody: Font = .callout.monospacedDigit()
    /// .caption.monospacedDigit() — Counts in badges, timestamps, table numerics
    static let numericCaption: Font = .caption.monospacedDigit()
}

// MARK: - DS-3: Opacity Scale

enum Opacity {
    static let rowTint: Double = 0.04
    static let badgeFill: Double = 0.12
    static let hoverHighlight: Double = 0.06
    static let disabled: Double = 0.5
    static let scrim: Double = 0.3
}

// MARK: - DS-4: Shadow Presets

extension View {
    func cardElevation() -> some View {
        shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
    func cardHoverElevation() -> some View {
        shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
    func popoverElevation() -> some View {
        shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
    func toastElevation() -> some View {
        shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}

// MARK: - DS-5: Animation Presets

enum Anim {
    /// Pause/resume, connect/disconnect
    static let stateChange: Animation = .snappy
    /// Layout changes, expand/collapse
    static let structural: Animation = .spring
    /// Sheet/popover/toast appearance
    static let entrance: Animation = .spring(duration: 0.4)
    /// Hover, selection, badge tick
    static let micro: Animation = .spring(duration: 0.2)

    /// Respects reduce motion preference
    static func effective(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .default : animation
    }
}

// MARK: - Path Utilities

extension String {
    /// Shorten an absolute path by replacing the home directory with ~.
    var shortenedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
