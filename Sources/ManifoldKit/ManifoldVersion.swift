// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// Single source of truth for the app version that the runtime helper
// reports to the app over XPC. Must stay in sync with the Manifold
// target's MARKETING_VERSION in project.yml — `gstack-ship` and the
// release process bump both together.
//
// Why this exists: the helper binary is built via SwiftPM (no Info.plist
// with CFBundleShortVersionString). Without a baked-in constant the
// helper had to hardcode a literal "0.4.0", which drifted from the app's
// real CFBundleShortVersionString every release. The drift fired the
// app's auto-restart-on-version-mismatch path on every launch, churning
// the XPC connection and breaking subsequent calls (e.g. + New Focus,
// settings toggles) that landed during the unstable window.
//
// Manual bump on release. Caught by tests in ManifoldKitTests if it
// drifts from project.yml.

import Foundation

public enum ManifoldVersion {
    /// Canonical app+helper version. Bump alongside project.yml's
    /// MARKETING_VERSION. The helper reports this; the app compares
    /// against its own `Bundle.main.shortVersionString`.
    public static let current: String = "0.5.0"
}
