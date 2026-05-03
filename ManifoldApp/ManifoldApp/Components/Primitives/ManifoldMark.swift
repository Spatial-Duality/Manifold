// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// ManifoldMark — the Manifold mark, { | }.
//
// Composed from Apple's `curlybraces` SF Symbol (which gives us correctly
// designed `{}` bracket glyphs at any weight, native template tinting,
// and the full symbolEffect catalog) plus a custom pipe Rectangle drawn
// between them. The trade-off vs. shipping a fully custom .symbolset:
// the pipe doesn't bounce when the brackets bounce — but the brackets
// are where attention goes, so the cost is small relative to the saved
// asset-catalog work.
//
// Color is always passed in (defaults to the primary text token).
// All sizing is via the explicit size parameter; the parent gives the
// frame, the SF Symbol fills it via .resizable() and the pipe scales
// proportionally.
//
// Reference: https://developer.apple.com/sf-symbols/

import SwiftUI

struct ManifoldMark: View {
    enum Placement {
        /// 18pt menu bar template image. Heavier weight reads at small sizes.
        case menubar
        /// Empty state, splash, large display surface. Light weight,
        /// considered.
        case display
        /// Inline marks (chips, headers). Mid-weight.
        case inline
    }

    enum PipeForm {
        /// Standard `|` pipe — default identity.
        case bar
        /// 20° tilted pipe — used for fleeting moments (hover, transition).
        case slash
    }

    var placement: Placement = .display
    var pipeForm: PipeForm = .bar
    var color: Color = ManifoldPalette.text

    var body: some View {
        // Custom SF Symbol shipped in
        // Assets.xcassets/Symbols/Manifold Icon SF.symbolset/.
        // Built from IBM Plex Sans Medium {|} glyphs in Apple's native
        // template format (one path per weight, three subpaths each:
        // left bracket, right bracket, pipe). All weight×scale variants
        // share identical artwork so the mark stays consistent across
        // .fontWeight() and .imageScale() modifiers.
        //
        // Image(_:) (not systemName) is the right initializer for
        // custom SF Symbols stored in the asset catalog.
        Image("Manifold Icon SF")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .rotationEffect(pipeForm == .slash ? .degrees(20) : .zero)
            .accessibilityLabel("Manifold")
    }
}

// MARK: - Previews

#Preview("ManifoldMark — sizes") {
    HStack(alignment: .center, spacing: 24) {
        VStack {
            ManifoldMark(placement: .menubar).frame(width: 18, height: 18)
            Text("18 menubar").font(ManifoldType.tiny)
        }
        VStack {
            ManifoldMark(placement: .inline).frame(width: 24, height: 24)
            Text("24 inline").font(ManifoldType.tiny)
        }
        VStack {
            ManifoldMark(placement: .inline).frame(width: 36, height: 36)
            Text("36 inline").font(ManifoldType.tiny)
        }
        VStack {
            ManifoldMark(placement: .display).frame(width: 80, height: 80)
            Text("80 display").font(ManifoldType.tiny)
        }
        VStack {
            ManifoldMark(placement: .display).frame(width: 140, height: 140)
            Text("140 display").font(ManifoldType.tiny)
        }
    }
    .padding(32)
    .background(ManifoldPalette.bg)
}

#Preview("ManifoldMark — slash form") {
    HStack(spacing: 32) {
        ManifoldMark(placement: .display, pipeForm: .bar)
            .frame(width: 200, height: 200)
        ManifoldMark(placement: .display, pipeForm: .slash)
            .frame(width: 200, height: 200)
    }
    .padding(32)
    .background(ManifoldPalette.bg)
}
