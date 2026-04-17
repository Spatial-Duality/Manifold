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

    @Test("Trusted Manifold app bundle can issue privileged app commands")
    func trustedAppAuthorizesPrivilegedCommand() {
        let authorization = ClientIdentityVerifier.authorizeCommand(
            name: "pause",
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/MacOS/Manifold",
            clientBundleIdentifier: "com.spatialduality.manifold"
        )

        #expect(authorization.role == .app)
        #expect(authorization.isAuthorized)
    }

    @Test("CLI is limited to read-only app commands")
    func cliIsLimitedToReadOnlyCommands() {
        let allowed = ClientIdentityVerifier.authorizeCommand(
            name: "getStatus",
            clientProcessID: 42,
            clientExecutablePath: "/usr/local/bin/manifold-cli",
            clientBundleIdentifier: nil
        )
        let denied = ClientIdentityVerifier.authorizeCommand(
            name: "pause",
            clientProcessID: 42,
            clientExecutablePath: "/usr/local/bin/manifold-cli",
            clientBundleIdentifier: nil
        )

        #expect(allowed.role == .cli)
        #expect(allowed.isAuthorized)
        #expect(denied.role == .cli)
        #expect(denied.isAuthorized == false)
        #expect(denied.reason.contains("read-only"))
    }

    @Test("MCP helper is denied app commands")
    func mcpHelperCannotIssueAppCommands() {
        let authorization = ClientIdentityVerifier.authorizeCommand(
            name: "pause",
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/Library/LaunchServices/manifold-mcp",
            clientBundleIdentifier: nil
        )

        #expect(authorization.role == .mcp)
        #expect(authorization.isAuthorized == false)
        #expect(authorization.reason.contains("connect/callTool"))
    }

    @Test("Privileged app commands reject callers signed by the wrong team")
    func privilegedCommandsRejectWrongTeam() {
        let authorization = ClientIdentityVerifier.authorizeCommand(
            name: "pause",
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/MacOS/Manifold",
            clientBundleIdentifier: "com.spatialduality.manifold",
            clientAttestation: ProcessAttestation(
                processID: 42,
                identifier: "com.spatialduality.manifold",
                teamIdentifier: "WRONGTEAM",
                signatureValid: true,
                usedAuditToken: true
            ),
            runtimeTeamIdentifier: "9FHKB788RP",
            signatureRequirementSatisfied: false
        )

        #expect(authorization.role == .app)
        #expect(authorization.isAuthorized == false)
        #expect(authorization.reason.contains("team identifier"))
    }

    @Test("Signed runtime mode rejects helper signed by the wrong team")
    func signedRuntimeRejectsWrongHelperTeam() {
        let identity = ClientIdentityVerifier.verify(
            requestedAgent: TargetApp.cowork.rawValue,
            clientProcessID: 42,
            clientExecutablePath: "/Applications/Manifold.app/Contents/Library/LaunchServices/manifold-mcp",
            hostProcessID: 99,
            hostBundleIdentifier: "com.anthropic.claudefordesktop",
            hostExecutablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
            clientAttestation: ProcessAttestation(
                processID: 42,
                identifier: "manifold-mcp",
                teamIdentifier: "WRONGTEAM",
                signatureValid: true,
                usedAuditToken: true
            ),
            hostAttestation: ProcessAttestation(
                processID: 99,
                identifier: "com.anthropic.claudefordesktop",
                teamIdentifier: "CLAUDETEAM",
                signatureValid: true,
                usedAuditToken: false
            ),
            runtimeTeamIdentifier: "9FHKB788RP",
            clientRequirementSatisfied: false,
            hostRequirementSatisfied: true
        )

        #expect(identity.status == .unverified)
        #expect(identity.reason.contains("same team"))
    }
}
