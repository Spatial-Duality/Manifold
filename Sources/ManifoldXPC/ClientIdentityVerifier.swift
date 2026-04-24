// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import ManifoldKit
import Darwin

enum ClientIdentityVerifier {
    private static let supportedHosts: [String: TargetApp] = [
        "com.anthropic.claudefordesktop": .cowork,
        "com.openai.codex": .codex,
    ]
    private static let trustedAppBundleIdentifiers: Set<String> = [
        "com.spatialduality.manifold",
    ]
    private static let readOnlyCLICommands: Set<String> = [
        "ping",
        "getStatus",
        "dataControlSummary",
        "recentActivity",
        "listSources",
    ]

    enum CommandCallerRole: String, Sendable {
        case app
        case cli
        case mcp
        case unknown
    }

    struct AppCommandAuthorization: Sendable {
        let role: CommandCallerRole
        let isAuthorized: Bool
        let clientProcessID: pid_t
        let clientExecutablePath: String?
        let clientBundleIdentifier: String?
        let reason: String
    }

    static func verify(requestedAgent: String, connection: NSXPCConnection?) -> VerifiedClientIdentity {
        guard let connection else {
            return VerifiedClientIdentity(
                requestedTargetApp: requestedAgent,
                effectiveTargetApp: nil,
                clientProcessID: -1,
                clientExecutablePath: nil,
                hostProcessID: nil,
                hostBundleIdentifier: nil,
                hostExecutablePath: nil,
                status: .unknown,
                reason: "No XPC connection context was available for verification."
            )
        }

        let clientPID = connection.processIdentifier
        let clientPath = processPath(for: clientPID)
        let clientAttestation = SignedProcessVerifier.attestation(for: connection)
        let clientName = clientPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unknown"
        guard clientName == "manifold-mcp" else {
            return VerifiedClientIdentity(
                requestedTargetApp: requestedAgent,
                effectiveTargetApp: nil,
                clientProcessID: clientPID,
                clientExecutablePath: clientPath,
                hostProcessID: nil,
                hostBundleIdentifier: nil,
                hostExecutablePath: nil,
                status: .unverified,
                reason: "Unexpected XPC peer executable \(clientName)."
            )
        }

        let hostPID = parentProcessIdentifier(for: clientPID)
        let hostExecutablePath = hostPID.flatMap { processPath(for: $0) }
        let hostApplication = hostPID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let hostBundleIdentifier = hostApplication?.bundleIdentifier
            ?? inferredBundleIdentifier(from: hostExecutablePath)
        let runtimeTeamIdentifier = strictRuntimeTeamIdentifier()
        let clientRequirementSatisfied: Bool? = {
            guard let runtimeTeamIdentifier,
                  let identifier = clientAttestation?.identifier ?? clientPath.map({ URL(fileURLWithPath: $0).lastPathComponent }) else {
                return nil
            }
            return SignedProcessVerifier.satisfiesDesignatedRequirement(
                processID: clientPID,
                identifier: identifier,
                teamIdentifier: runtimeTeamIdentifier
            )
        }()
        let hostAttestation = hostPID.flatMap { SignedProcessVerifier.attestation(processID: $0) }
        let hostRequirementSatisfied: Bool? = {
            guard let hostPID,
                  let hostBundleIdentifier else {
                return nil
            }
            return SignedProcessVerifier.satisfiesDesignatedRequirement(
                processID: hostPID,
                identifier: hostBundleIdentifier,
                teamIdentifier: nil
            )
        }()
        return verify(
            requestedAgent: requestedAgent,
            clientProcessID: clientPID,
            clientExecutablePath: clientPath,
            hostProcessID: hostPID,
            hostBundleIdentifier: hostBundleIdentifier,
            hostExecutablePath: hostExecutablePath,
            clientAttestation: clientAttestation,
            hostAttestation: hostAttestation,
            runtimeTeamIdentifier: runtimeTeamIdentifier,
            clientRequirementSatisfied: clientRequirementSatisfied,
            hostRequirementSatisfied: hostRequirementSatisfied
        )
    }

    static func authorizeCommand(name: String, connection: NSXPCConnection?) -> AppCommandAuthorization {
        guard let connection else {
            return AppCommandAuthorization(
                role: .unknown,
                isAuthorized: false,
                clientProcessID: -1,
                clientExecutablePath: nil,
                clientBundleIdentifier: nil,
                reason: "No XPC connection context was available for app command authorization."
            )
        }

        let clientPID = connection.processIdentifier
        let clientExecutablePath = processPath(for: clientPID)
        let clientBundleIdentifier = NSRunningApplication(processIdentifier: clientPID)?.bundleIdentifier
            ?? inferredAppBundleIdentifier(from: clientExecutablePath)
        let runtimeTeamIdentifier = strictRuntimeTeamIdentifier()
        return authorizeCommand(
            name: name,
            clientProcessID: clientPID,
            clientExecutablePath: clientExecutablePath,
            clientBundleIdentifier: clientBundleIdentifier,
            clientAttestation: SignedProcessVerifier.attestation(for: connection),
            runtimeTeamIdentifier: runtimeTeamIdentifier,
            signatureRequirementSatisfied: {
                guard let runtimeTeamIdentifier,
                      trustedAppBundleIdentifiers.contains(clientBundleIdentifier ?? "") else {
                    return nil
                }
                return SignedProcessVerifier.satisfiesDesignatedRequirement(
                    processID: clientPID,
                    identifier: clientBundleIdentifier ?? "com.spatialduality.manifold",
                    teamIdentifier: runtimeTeamIdentifier
                )
            }()
        )
    }

    static func authorizeCommand(
        name: String,
        clientProcessID: pid_t,
        clientExecutablePath: String?,
        clientBundleIdentifier: String?,
        clientAttestation: ProcessAttestation? = nil,
        runtimeTeamIdentifier: String? = nil,
        signatureRequirementSatisfied: Bool? = nil
    ) -> AppCommandAuthorization {
        let executableName = clientExecutablePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unknown"
        if trustedAppBundleIdentifiers.contains(clientBundleIdentifier ?? "") {
            if let runtimeTeamIdentifier = strictRuntimeTeamIdentifier(runtimeTeamIdentifier) {
                guard let clientAttestation else {
                    return AppCommandAuthorization(
                        role: .app,
                        isAuthorized: false,
                        clientProcessID: clientProcessID,
                        clientExecutablePath: clientExecutablePath,
                        clientBundleIdentifier: clientBundleIdentifier,
                        reason: "Missing caller code-signing attestation for privileged app command."
                    )
                }
                guard clientAttestation.signatureValid else {
                    return AppCommandAuthorization(
                        role: .app,
                        isAuthorized: false,
                        clientProcessID: clientProcessID,
                        clientExecutablePath: clientExecutablePath,
                        clientBundleIdentifier: clientBundleIdentifier,
                        reason: "Caller signature is invalid for privileged app command."
                    )
                }
                guard clientAttestation.teamIdentifier == runtimeTeamIdentifier else {
                    return AppCommandAuthorization(
                        role: .app,
                        isAuthorized: false,
                        clientProcessID: clientProcessID,
                        clientExecutablePath: clientExecutablePath,
                        clientBundleIdentifier: clientBundleIdentifier,
                        reason: "Caller team identifier does not match the Manifold runtime."
                    )
                }
                if signatureRequirementSatisfied == false {
                    return AppCommandAuthorization(
                        role: .app,
                        isAuthorized: false,
                        clientProcessID: clientProcessID,
                        clientExecutablePath: clientExecutablePath,
                        clientBundleIdentifier: clientBundleIdentifier,
                        reason: "Caller failed the designated requirement for privileged app commands."
                    )
                }
            }
            return AppCommandAuthorization(
                role: .app,
                isAuthorized: true,
                clientProcessID: clientProcessID,
                clientExecutablePath: clientExecutablePath,
                clientBundleIdentifier: clientBundleIdentifier,
                reason: "Trusted Manifold app bundle authorized app command."
            )
        }

        if executableName == "manifold-cli" {
            let isAuthorized = readOnlyCLICommands.contains(name)
            if isAuthorized,
               let runtimeTeamIdentifier = strictRuntimeTeamIdentifier(runtimeTeamIdentifier),
               let clientAttestation,
               clientAttestation.signatureValid,
               let callerTeamIdentifier = clientAttestation.teamIdentifier,
               callerTeamIdentifier != runtimeTeamIdentifier {
                return AppCommandAuthorization(
                    role: .cli,
                    isAuthorized: false,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    clientBundleIdentifier: clientBundleIdentifier,
                    reason: "CLI signature does not match the Manifold runtime."
                )
            }
            return AppCommandAuthorization(
                role: .cli,
                isAuthorized: isAuthorized,
                clientProcessID: clientProcessID,
                clientExecutablePath: clientExecutablePath,
                clientBundleIdentifier: clientBundleIdentifier,
                reason: isAuthorized
                    ? "Read-only CLI command authorized."
                    : "CLI access is limited to read-only status commands."
            )
        }

        if executableName == "manifold-mcp" {
            return AppCommandAuthorization(
                role: .mcp,
                isAuthorized: false,
                clientProcessID: clientProcessID,
                clientExecutablePath: clientExecutablePath,
                clientBundleIdentifier: clientBundleIdentifier,
                reason: "The MCP helper must use connect/callTool, not app commands."
            )
        }

        return AppCommandAuthorization(
            role: .unknown,
            isAuthorized: false,
            clientProcessID: clientProcessID,
            clientExecutablePath: clientExecutablePath,
            clientBundleIdentifier: clientBundleIdentifier,
            reason: "Untrusted local process is not allowed to call app commands."
        )
    }

    static func verify(
        requestedAgent: String,
        clientProcessID: pid_t,
        clientExecutablePath: String?,
        hostProcessID: pid_t?,
        hostBundleIdentifier: String?,
        hostExecutablePath: String?,
        clientAttestation: ProcessAttestation? = nil,
        hostAttestation: ProcessAttestation? = nil,
        runtimeTeamIdentifier: String? = nil,
        clientRequirementSatisfied: Bool? = nil,
        hostRequirementSatisfied: Bool? = nil
    ) -> VerifiedClientIdentity {
        let effectiveTargetApp = hostBundleIdentifier
            .flatMap { supportedHosts[$0] }
            ?? inferredTargetApp(fromExecutablePath: hostExecutablePath)

        guard let effectiveTargetApp else {
            return VerifiedClientIdentity(
                requestedTargetApp: requestedAgent,
                effectiveTargetApp: nil,
                clientProcessID: clientProcessID,
                clientExecutablePath: clientExecutablePath,
                hostProcessID: hostProcessID,
                hostBundleIdentifier: hostBundleIdentifier,
                hostExecutablePath: hostExecutablePath,
                status: .unverified,
                reason: "Unsupported host application \(hostBundleIdentifier ?? hostExecutablePath ?? "unknown")."
            )
        }

        if let runtimeTeamIdentifier = strictRuntimeTeamIdentifier(runtimeTeamIdentifier) {
            guard let clientAttestation else {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "Missing code-signing attestation for the manifold-mcp helper."
                )
            }
            guard clientAttestation.signatureValid else {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "The manifold-mcp helper signature is invalid."
                )
            }
            guard clientAttestation.teamIdentifier == runtimeTeamIdentifier else {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "The manifold-mcp helper is not signed by the same team as the runtime."
                )
            }
            if clientRequirementSatisfied == false {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "The manifold-mcp helper failed the designated requirement check."
                )
            }
            guard let hostAttestation else {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "Missing host application code-signing attestation."
                )
            }
            guard hostAttestation.signatureValid else {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "The host application's signature is invalid."
                )
            }
            if hostRequirementSatisfied == false {
                return VerifiedClientIdentity(
                    requestedTargetApp: requestedAgent,
                    effectiveTargetApp: effectiveTargetApp.rawValue,
                    clientProcessID: clientProcessID,
                    clientExecutablePath: clientExecutablePath,
                    hostProcessID: hostProcessID,
                    hostBundleIdentifier: hostBundleIdentifier,
                    hostExecutablePath: hostExecutablePath,
                    status: .unverified,
                    reason: "The host application failed the designated requirement check."
                )
            }
        }

        guard requestedAgent == effectiveTargetApp.rawValue else {
            return VerifiedClientIdentity(
                requestedTargetApp: requestedAgent,
                effectiveTargetApp: effectiveTargetApp.rawValue,
                clientProcessID: clientProcessID,
                clientExecutablePath: clientExecutablePath,
                hostProcessID: hostProcessID,
                hostBundleIdentifier: hostBundleIdentifier,
                hostExecutablePath: hostExecutablePath,
                status: .unverified,
                reason: "Requested agent \(requestedAgent) does not match verified host \(effectiveTargetApp.rawValue)."
            )
        }

        return VerifiedClientIdentity(
            requestedTargetApp: requestedAgent,
            effectiveTargetApp: effectiveTargetApp.rawValue,
            clientProcessID: clientProcessID,
            clientExecutablePath: clientExecutablePath,
            hostProcessID: hostProcessID,
            hostBundleIdentifier: hostBundleIdentifier,
            hostExecutablePath: hostExecutablePath,
            status: .verified,
            reason: "Verified through the XPC peer process and host application."
        )
    }

    private static func processPath(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        let maxPathSize = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: maxPathSize)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        let bytes = buffer.prefix(Int(result)).map { UInt8(bitPattern: $0) }
        let trimmed = bytes.last == 0 ? bytes.dropLast() : bytes[bytes.startIndex...]
        return String(decoding: trimmed, as: UTF8.self)
    }

    private static func parentProcessIdentifier(for pid: pid_t) -> pid_t? {
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = withUnsafeMutablePointer(to: &process) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: size) { rawPointer in
                sysctl(&mib, u_int(mib.count), rawPointer, &size, nil, 0)
            }
        }
        guard result == 0, size > 0 else { return nil }
        return process.kp_eproc.e_ppid
    }

    private static func inferredBundleIdentifier(from executablePath: String?) -> String? {
        guard let executablePath else { return nil }
        let lowercased = executablePath.lowercased()
        if lowercased.contains("claude.app") {
            return "com.anthropic.claudefordesktop"
        }
        if lowercased.contains("codex.app") {
            return "com.openai.codex"
        }
        return nil
    }

    private static func inferredAppBundleIdentifier(from executablePath: String?) -> String? {
        guard let executablePath else { return nil }
        let lowercased = executablePath.lowercased()
        if lowercased.contains("manifold.app/contents/macos") {
            return "com.spatialduality.manifold"
        }
        return nil
    }

    private static func inferredTargetApp(fromExecutablePath executablePath: String?) -> TargetApp? {
        guard let executablePath else { return nil }
        let lowercased = executablePath.lowercased()
        if lowercased.contains("claude") {
            return .cowork
        }
        if lowercased.contains("codex") {
            return .codex
        }
        return nil
    }

    private static func strictRuntimeTeamIdentifier(_ explicit: String? = nil) -> String? {
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        guard let attestation = SignedProcessVerifier.currentProcessAttestation(),
              attestation.signatureValid,
              let teamIdentifier = attestation.teamIdentifier,
              !teamIdentifier.isEmpty else {
            return nil
        }
        return teamIdentifier
    }
}
