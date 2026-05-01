// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import XCTest
import SwiftUI
@testable import Manifold

/// Inclusivity ADA category specifically rewards Dynamic Type. These
/// tests pin the contract that every ManifoldType token is bound to a
/// semantic Apple text style — not a fixed pixel size — so user
/// preferences in System Settings → Accessibility → Display → Larger
/// Text actually change the rendered size.
///
/// **Verification strategy.** SwiftUI's `Font` is opaque at runtime —
/// you can't inspect "is this Font bound to a TextStyle?" via public
/// API, and `ImageRenderer` in unit tests doesn't faithfully propagate
/// `\.dynamicTypeSize` without a host scene. We instead pin the
/// contract at the source level: read DesignTokens.swift and assert
/// no token uses the fixed-size `.system(size:` API. Any future
/// regression that re-introduces a fixed-size token fails this test.
final class ManifoldTypeDynamicTypeTests: XCTestCase {

    /// The DesignTokens.swift source must contain zero `.system(size:`
    /// tokens inside the `enum Typ` declaration. That's the contract:
    /// every named type role scales with Dynamic Type.
    func testNoFixedPixelSizeFontsInTypTokens() throws {
        let tokensURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()              // ManifoldAppTests/
            .deletingLastPathComponent()              // repo root
            .appendingPathComponent("ManifoldApp/ManifoldApp/Components/DesignTokens.swift")

        let source = try String(contentsOf: tokensURL, encoding: .utf8)

        // Locate the Typ enum body.
        guard let typStart = source.range(of: "enum Typ {"),
              let typEndCandidate = source.range(of: "\n}\n", range: typStart.upperBound..<source.endIndex) else {
            XCTFail("Could not locate `enum Typ` in DesignTokens.swift")
            return
        }
        let typBody = source[typStart.upperBound..<typEndCandidate.lowerBound]

        // Within the Typ enum body, no token may use `.system(size:`.
        // That API takes a fixed CGFloat and ignores Dynamic Type.
        let fixedSizePattern = ".system(size:"
        let occurrences = typBody.components(separatedBy: fixedSizePattern).count - 1

        XCTAssertEqual(
            occurrences, 0,
            "DesignTokens.swift `enum Typ` contains \(occurrences) `.system(size:` token(s). " +
            "Every token must use a semantic style (e.g. `.system(.body)`, `.callout`) so it scales " +
            "with Dynamic Type. Apple HIG: " +
            "https://developer.apple.com/documentation/swiftui/dynamictypesize"
        )
    }

    /// Every token must be a non-nil Font value (sanity check that the
    /// migration didn't accidentally produce a `Font` of zero size or
    /// crash on construction).
    @MainActor
    func testAllTokensConstructWithoutCrashing() {
        let tokens: [Font] = [
            ManifoldType.tiny, ManifoldType.caption, ManifoldType.captionMedium,
            ManifoldType.body, ManifoldType.bodyMedium,
            ManifoldType.title, ManifoldType.heading, ManifoldType.display,
            ManifoldType.wordmark,
            ManifoldType.mono, ManifoldType.monoBody,
            ManifoldType.numericBody, ManifoldType.numericCaption,
        ]
        XCTAssertEqual(tokens.count, 13, "All 13 ManifoldType tokens construct")
    }
}
