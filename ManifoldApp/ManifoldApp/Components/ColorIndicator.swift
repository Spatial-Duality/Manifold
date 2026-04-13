// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Reusable colored dot indicator.
/// Replaces 15+ instances of `Circle().fill(color).frame(width: N, height: N)` across the codebase.
struct ColorIndicator: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
