// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit
@testable import ManifoldXPC

@Suite("ClientIdentityVerifier")
struct ClientIdentityVerifierTests {
    @Test("Nil connection reports unknown verification")
    func nilConnectionReportsUnknown() {
        let identity = ClientIdentityVerifier.verify(requestedAgent: TargetApp.cowork.rawValue, connection: nil)

        #expect(identity.status == .unknown)
        #expect(identity.effectiveTargetApp == nil)
    }

    @Test("Supported Claude host verifies Claude target")
    func supportedClaudeHostVerifies() {
        let identity = ClientIdentityVerifier.verify(
            requestedAgent: TargetApp.cowork.rawValue,
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/Library/LaunchServices/manifold-mcp",
            hostProcessID: 99,
            hostBundleIdentifier: "com.anthropic.claudefordesktop",
            hostExecutablePath: "/Applications/Claude.app/Contents/MacOS/Claude"
        )

        #expect(identity.status == .verified)
        #expect(identity.effectiveTargetApp == TargetApp.cowork.rawValue)
    }

    @Test("Supported Codex host verifies Codex target")
    func supportedCodexHostVerifies() {
        let identity = ClientIdentityVerifier.verify(
            requestedAgent: TargetApp.codex.rawValue,
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/Library/LaunchServices/manifold-mcp",
            hostProcessID: 100,
            hostBundleIdentifier: "com.openai.codex",
            hostExecutablePath: "/Applications/Codex.app/Contents/MacOS/Codex"
        )

        #expect(identity.status == .verified)
        #expect(identity.effectiveTargetApp == TargetApp.codex.rawValue)
    }

    @Test("Requested agent mismatch is rejected")
    func requestedAgentMismatchRejected() {
        let identity = ClientIdentityVerifier.verify(
            requestedAgent: TargetApp.codex.rawValue,
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/Library/LaunchServices/manifold-mcp",
            hostProcessID: 99,
            hostBundleIdentifier: "com.anthropic.claudefordesktop",
            hostExecutablePath: "/Applications/Claude.app/Contents/MacOS/Claude"
        )

        #expect(identity.status == .unverified)
        #expect(identity.effectiveTargetApp == TargetApp.cowork.rawValue)
    }

    @Test("Unsupported host is unverified")
    func unsupportedHostRejected() {
        let identity = ClientIdentityVerifier.verify(
            requestedAgent: TargetApp.cowork.rawValue,
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/Library/LaunchServices/manifold-mcp",
            hostProcessID: 101,
            hostBundleIdentifier: "com.example.other",
            hostExecutablePath: "/Applications/Other.app/Contents/MacOS/Other"
        )

        #expect(identity.status == .unverified)
        #expect(identity.effectiveTargetApp == nil)
    }
}
