// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// TriStateCheckbox — on / off / mixed, with an optional override dot.
//
// Used throughout the Access file tree. The override dot signals "this
// item's state was set manually, overriding its parent/rule default".

import SwiftUI

struct TriStateCheckbox: View {
    enum State { case off, on, mixed }

    @Binding var state: State
    var override: Bool = false
    var color: Color = ManifoldPalette.claude
    var size: CGFloat = 16

    var body: some View {
        Button {
            state = (state == .on) ? .off : .on
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(ManifoldPalette.border2, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(state == .off ? ManifoldPalette.surface : color)
                    )
                    .frame(width: size, height: size)

                switch state {
                case .on:
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.62, weight: .bold))
                        .foregroundStyle(.white)
                case .mixed:
                    Rectangle()
                        .fill(color)
                        .frame(width: size * 0.45, height: 2)
                case .off:
                    EmptyView()
                }

                if override {
                    Circle()
                        .fill(ManifoldPalette.attention)
                        .frame(width: 4, height: 4)
                        .offset(x: size * 0.55, y: -size * 0.55)
                        .accessibilityLabel("Manually overridden")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(state == .on ? .isSelected : [])
    }

    private var label: String {
        switch state {
        case .on:    return override ? "Checked — manually overridden" : "Checked"
        case .off:   return override ? "Unchecked — manually overridden" : "Unchecked"
        case .mixed: return "Partially checked"
        }
    }
}

#Preview("Tri-state checkbox") {
    struct Demo: View {
        @SwiftUI.State private var a: TriStateCheckbox.State = .on
        @SwiftUI.State private var b: TriStateCheckbox.State = .off
        @SwiftUI.State private var c: TriStateCheckbox.State = .mixed
        @SwiftUI.State private var d: TriStateCheckbox.State = .on
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                TriStateCheckbox(state: $a)
                TriStateCheckbox(state: $b)
                TriStateCheckbox(state: $c)
                TriStateCheckbox(state: $d, override: true)
            }
            .padding(Spacing.s6)
            .background(ManifoldPalette.bg)
        }
    }
    return Demo()
}
