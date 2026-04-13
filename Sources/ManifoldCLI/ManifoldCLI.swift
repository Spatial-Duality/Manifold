// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldXPC

@main
struct ManifoldCLI {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "status":
            try await handleStatus()
        case "log", "activity":
            try await handleLog(Array(args.dropFirst()))
        case "sources":
            try await handleSources()
        case "pause":
            try await handlePause(Array(args.dropFirst()))
        case "resume":
            try await handleResume(Array(args.dropFirst()))
        case "install":
            try handleInstall()
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        manifold-cli — Manifold MCP administration

        Commands:
          status     Show connection status and stats
          log        Show recent MCP activity
          activity   Alias for log
          sources    List approved sources
          pause      Pause an agent (default: cowork)
          resume     Resume an agent (default: cowork)
          install    Install MCP server into Claude Desktop and Codex configs
        """)
    }

    static func handleStatus() async throws {
        let xpc = ManifoldXPCClient()
        let result = try await xpc.command(name: "getStatus")
        let sources = result["sources"] as? [[String: Any]] ?? []
        let activeBridgeCount = result["activeBridgeCount"] as? Int ?? 0
        let pendingApprovalCount = result["pendingApprovalCount"] as? Int ?? 0

        print("Runtime: Connected")
        print("Active connections: \(activeBridgeCount)")
        print("Configured sources: \(sources.count)")
        print("Pending approvals: \(pendingApprovalCount)")
    }

    static func handleLog(_ args: [String]) async throws {
        let limit = Int(args.first ?? "20") ?? 20
        let xpc = ManifoldXPCClient()
        let result = try await xpc.command(name: "recentActivity", payload: ["limit": limit])
        let entries = result["entries"] as? [[String: Any]] ?? []
        for entry in entries.reversed() {
            let timestamp = entry["timestamp"] as? String ?? ""
            let action = entry["action"] as? String ?? ""
            let path = entry["filePath"] as? String ?? ""
            print("[\(timestamp)] \(action) \(path)")
        }
    }

    static func handleSources() async throws {
        let xpc = ManifoldXPCClient()
        let result = try await xpc.command(name: "listSources")
        let sources = result["sources"] as? [[String: Any]] ?? []
        if sources.isEmpty {
            print("No approved sources. Use the Manifold app to add sources.")
        } else {
            for source in sources {
                let path = source["originalRootPath"] as? String ?? "(unknown)"
                let status = source["status"] as? String ?? "unknown"
                print("\(path) [\(status)]")
            }
        }
    }

    static func handlePause(_ args: [String]) async throws {
        let agent = args.first ?? "cowork"
        let xpc = ManifoldXPCClient()
        _ = try await xpc.command(name: "pauseAgent", payload: ["agent": agent])
        print("Paused \(agent).")
    }

    static func handleResume(_ args: [String]) async throws {
        let agent = args.first ?? "cowork"
        let xpc = ManifoldXPCClient()
        _ = try await xpc.command(name: "resumeAgent", payload: ["agent": agent])
        print("Resumed \(agent).")
    }

    static func handleInstall() throws {
        let binaryPath = ProcessInfo.processInfo.environment["MANIFOLD_MCP_PATH"]
            ?? "\(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path)/Manifold/bin/manifold-mcp"
        let writer = ConfigWriter(binaryPath: binaryPath)
        try writer.installAll()
        print("MCP server installed. Restart Claude Desktop to connect.")
    }
}
