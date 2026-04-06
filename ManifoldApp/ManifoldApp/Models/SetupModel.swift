import Foundation
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "setup")

@Observable
@MainActor
final class SetupModel {
    // MCP
    var mcpInstalled = false
    var installError: String?

    // Agent configs
    var claudeDesktopConfigured = false
    var codexConfigured = false

    // Onboarding
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "manifold.onboarding.completed") }
    }

    // Preferences
    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "manifold.launchAtLogin") }
    }
    var notifyOnSessionEnd: Bool {
        didSet { UserDefaults.standard.set(notifyOnSessionEnd, forKey: "manifold.notify.sessionEnd") }
    }
    var notifyOnAccessDenied: Bool {
        didSet { UserDefaults.standard.set(notifyOnAccessDenied, forKey: "manifold.notify.accessDenied") }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "manifold.onboarding.completed")
        launchAtLogin = UserDefaults.standard.bool(forKey: "manifold.launchAtLogin")
        notifyOnSessionEnd = UserDefaults.standard.object(forKey: "manifold.notify.sessionEnd") as? Bool ?? true
        notifyOnAccessDenied = UserDefaults.standard.object(forKey: "manifold.notify.accessDenied") as? Bool ?? true
    }

    func checkMCPInstalled() {
        mcpInstalled = FileManager.default.fileExists(atPath: ManifoldStore.mcpBinaryPath)
    }

    func checkAgentConfigs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDesktopConfigured = FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json").path
        )
        codexConfigured = FileManager.default.fileExists(
            atPath: home.appendingPathComponent(".codex/config.toml").path
        )
    }

    func installMCP() {
        installError = nil
        do {
            let destPath = ManifoldStore.mcpBinaryPath
            let destURL = URL(fileURLWithPath: destPath)
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bundled = Bundle.main.url(forResource: "manifold-mcp", withExtension: nil) {
                if FileManager.default.fileExists(atPath: destPath) { try FileManager.default.removeItem(at: destURL) }
                try FileManager.default.copyItem(at: bundled, to: destURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
            } else if !FileManager.default.fileExists(atPath: destPath) {
                let debugBin = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent(".build/debug/manifold-mcp")
                if FileManager.default.fileExists(atPath: debugBin.path) {
                    try FileManager.default.copyItem(at: debugBin, to: destURL)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
                } else {
                    installError = "MCP binary not found. Run: swift build --product manifold-mcp"
                    return
                }
            }
            try ConfigWriter(binaryPath: destPath).installAll()
            checkMCPInstalled()
            checkAgentConfigs()
        } catch {
            installError = "Install failed: \(error.localizedDescription)"
        }
    }
}
