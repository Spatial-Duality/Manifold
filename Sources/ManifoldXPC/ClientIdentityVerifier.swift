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
        let effectiveTargetApp = hostBundleIdentifier
            .flatMap { supportedHosts[$0] }
            ?? inferredTargetApp(fromExecutablePath: hostExecutablePath)

        guard let effectiveTargetApp else {
            return VerifiedClientIdentity(
                requestedTargetApp: requestedAgent,
                effectiveTargetApp: nil,
                clientProcessID: clientPID,
                clientExecutablePath: clientPath,
                hostProcessID: hostPID,
                hostBundleIdentifier: hostBundleIdentifier,
                hostExecutablePath: hostExecutablePath,
                status: .unverified,
                reason: "Unsupported host application \(hostBundleIdentifier ?? hostExecutablePath ?? "unknown")."
            )
        }

        guard requestedAgent == effectiveTargetApp.rawValue else {
            return VerifiedClientIdentity(
                requestedTargetApp: requestedAgent,
                effectiveTargetApp: effectiveTargetApp.rawValue,
                clientProcessID: clientPID,
                clientExecutablePath: clientPath,
                hostProcessID: hostPID,
                hostBundleIdentifier: hostBundleIdentifier,
                hostExecutablePath: hostExecutablePath,
                status: .unverified,
                reason: "Requested agent \(requestedAgent) does not match verified host \(effectiveTargetApp.rawValue)."
            )
        }

        return VerifiedClientIdentity(
            requestedTargetApp: requestedAgent,
            effectiveTargetApp: effectiveTargetApp.rawValue,
            clientProcessID: clientPID,
            clientExecutablePath: clientPath,
            hostProcessID: hostPID,
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
}
