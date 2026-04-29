// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Privacy Backend Kind")
struct PrivacyBackendKindTests {
    @Test("Legacy backend raw values decode to MLX")
    func legacyBackendRawValuesDecodeToMLX() throws {
        #expect(PrivacyBackendKind.fromStoredRawValue("mlx") == .mlx)
        #expect(PrivacyBackendKind.fromStoredRawValue("core_ml") == .mlx)
        #expect(PrivacyBackendKind.fromStoredRawValue("official_cli") == .mlx)

        let decoder = JSONDecoder()
        #expect(try decoder.decode(PrivacyBackendKind.self, from: Data(#""core_ml""#.utf8)) == .mlx)
        #expect(try decoder.decode(PrivacyBackendKind.self, from: Data(#""official_cli""#.utf8)) == .mlx)
    }
}
