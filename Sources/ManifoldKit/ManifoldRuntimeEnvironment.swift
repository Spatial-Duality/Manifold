// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ManifoldRuntimeEnvironment {
    public static let defaultXPCServiceName = "com.spatialduality.manifold.runtime"

    public static let xpcServiceNameKey = "MANIFOLD_XPC_SERVICE_NAME"
    public static let runtimeStoreURLKey = "MANIFOLD_RUNTIME_STORE_URL"
    public static let appSupportRootURLKey = "MANIFOLD_APP_SUPPORT_ROOT"
    public static let launchAgentPlistURLKey = "MANIFOLD_LAUNCH_AGENT_PLIST_URL"
    public static let diagnosticsDirectoryURLKey = "MANIFOLD_DIAGNOSTICS_DIR"
    public static let testHomeKey = "MANIFOLD_TEST_HOME"
    public static let testScenarioKey = "MANIFOLD_TEST_SCENARIO"
    public static let protectedStorageTestKey = "MANIFOLD_TEST_PROTECTED_STORAGE_KEY"
    public static let allowUITestRunnerMCPKey = "MANIFOLD_TEST_ALLOW_UI_RUNNER_MCP"
    public static let testAgentVersionOverrideKey = "MANIFOLD_TEST_AGENT_VERSION_OVERRIDE"

    public static func string(
        for key: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    public static func url(
        for key: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let path = string(for: key, env: env) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: false)
    }

    public static func testHomeURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        url(for: testHomeKey, env: env)
    }

    public static func xpcServiceName(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let explicit = string(for: xpcServiceNameKey, env: env) {
            return explicit
        }
        if let testHome = testHomeURL(env: env) {
            return derivedXPCServiceName(for: testHome)
        }
        return defaultXPCServiceName
    }

    public static func runtimeStoreURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicit = url(for: runtimeStoreURLKey, env: env) {
            return explicit
        }
        if let testHome = testHomeURL(env: env) {
            return testHome.appendingPathComponent("runtime-store", isDirectory: true)
        }
        return appSupportRootURL(env: env)?
            .appendingPathComponent("Manifold", isDirectory: true)
            .appendingPathComponent("store", isDirectory: true)
    }

    public static func appSupportRootURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicit = url(for: appSupportRootURLKey, env: env) {
            return explicit
        }
        if let testHome = testHomeURL(env: env) {
            return testHome.appendingPathComponent("app-support", isDirectory: true)
        }
        return userApplicationSupportRootURL()
    }

    public static func diagnosticsDirectoryURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicit = url(for: diagnosticsDirectoryURLKey, env: env) {
            return explicit
        }
        if let testHome = testHomeURL(env: env) {
            return testHome.appendingPathComponent("diagnostics", isDirectory: true)
        }
        return appSupportRootURL(env: env)?
            .appendingPathComponent("Manifold", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public static func launchAgentPlistURL(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicit = url(for: launchAgentPlistURLKey, env: env) {
            return explicit
        }
        guard let testHome = testHomeURL(env: env) else { return nil }
        return testHome
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(xpcServiceName(env: env)).plist", isDirectory: false)
    }

    public static func helperEnvironment(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var forwarded: [String: String] = [:]
        for key in [
            xpcServiceNameKey,
            runtimeStoreURLKey,
            appSupportRootURLKey,
            launchAgentPlistURLKey,
            diagnosticsDirectoryURLKey,
            testHomeKey,
            protectedStorageTestKey,
            allowUITestRunnerMCPKey,
            testAgentVersionOverrideKey,
        ] {
            if let value = string(for: key, env: env) {
                forwarded[key] = value
            }
        }
        return forwarded
    }

    private static func derivedXPCServiceName(for testHome: URL) -> String {
        let suffix = testHome.lastPathComponent
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9.-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !suffix.isEmpty else { return defaultXPCServiceName }
        return "\(defaultXPCServiceName).\(suffix)"
    }

    private static func userApplicationSupportRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
    }
}
