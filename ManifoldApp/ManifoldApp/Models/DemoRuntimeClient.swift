// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User-facing synthetic runtime for Demo Mode.
///
/// The concrete data is built by `FixtureRuntimeClient` under the `.demo` profile
/// so demo mode can reuse the same app-facing protocol surface as tests without
/// touching live files, mail, or the local runtime stores.
typealias DemoRuntimeClient = FixtureRuntimeClient

extension DemoRuntimeClient {
    static func anthropologie() -> DemoRuntimeClient {
        DemoRuntimeClient(profile: .demo)
    }
}
