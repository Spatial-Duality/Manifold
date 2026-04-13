// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("ManifoldNotifications")
struct NotificationTests {
    @Test("Notification names are unique")
    func uniqueNames() {
        let names = [
            ManifoldNotification.agentConnected,
            ManifoldNotification.agentDisconnected,
            ManifoldNotification.accessDenied,
            ManifoldNotification.fileAccessed,
        ]
        let unique = Set(names)
        #expect(unique.count == 4)
    }

    @Test("Notification names use reverse-DNS format")
    func reverseDNS() {
        #expect(ManifoldNotification.agentConnected.rawValue.hasPrefix("com.spatialduality.manifold."))
        #expect(ManifoldNotification.agentDisconnected.rawValue.hasPrefix("com.spatialduality.manifold."))
        #expect(ManifoldNotification.accessDenied.rawValue.hasPrefix("com.spatialduality.manifold."))
        #expect(ManifoldNotification.fileAccessed.rawValue.hasPrefix("com.spatialduality.manifold."))
    }
}
