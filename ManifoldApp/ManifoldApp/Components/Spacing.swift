// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// Spacing — 4pt vertical baseline, 8pt horizontal grid.
// Matches design/html/tokens.css (--s-1 .. --s-9, --r-1 .. --r-6).
//
// Legacy names (tight/standard/section/edge/large/xlarge,
// cornerSmall/cornerMedium/cornerLarge) are preserved so existing views
// compile. New code should prefer the numbered tokens (`s1` .. `s9`,
// `r1` .. `r6`) that match the mockup CSS.

import SwiftUI

enum Spacing {
    // MARK: - 4pt baseline tokens (tokens.css --s-N)
    static let s1: CGFloat = 4    // tight
    static let s2: CGFloat = 8    // standard
    static let s3: CGFloat = 12   // section
    static let s4: CGFloat = 16   // card inner
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24   // edge
    static let s7: CGFloat = 32
    static let s8: CGFloat = 40
    static let s9: CGFloat = 48

    // MARK: - Legacy semantic names (kept)
    /// 4pt — tight inline spacing (icon-to-text gaps).
    static let tight: CGFloat = s1
    /// 8pt — standard list row internal padding.
    static let standard: CGFloat = s2
    /// 12pt — section spacing within a view.
    static let section: CGFloat = s3
    /// 16pt — standard view edge padding.
    static let edge: CGFloat = s4
    /// 24pt — section separation.
    static let large: CGFloat = s6
    /// 32pt — large separation between major sections.
    static let xlarge: CGFloat = s7

    // MARK: - Radii (tokens.css --r-N)
    static let r1: CGFloat = 3    // small pills, chips
    static let r2: CGFloat = 5    // buttons
    static let r3: CGFloat = 6    // cards, rows
    static let r4: CGFloat = 8    // inspector panels
    static let r5: CGFloat = 10   // windows
    static let r6: CGFloat = 12   // menu bar panel

    // MARK: - Legacy radii
    /// 6pt — inline pills, command row hover.
    static let cornerSmall: CGFloat = r3
    /// 10pt — cards, stat containers.
    static let cornerMedium: CGFloat = r5
    /// 12pt — section cards, overlays.
    static let cornerLarge: CGFloat = r6
}
