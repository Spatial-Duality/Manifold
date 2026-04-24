// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// Thin async client for talking to the local Manifold runtime over XPC.
public final class ManifoldXPCClient: @unchecked Sendable {
    /// Mach service name exposed by the local runtime helper.
    public static var serviceName: String {
        ManifoldRuntimeEnvironment.xpcServiceName()
    }

    private let lock = NSLock()
    private var connection: NSXPCConnection?

    /// Creates a client that lazily connects to the runtime helper.
    public init() {}

    /// Calls a governed MCP-style tool on behalf of an existing runtime connection.
    public func callTool(
        connectionID: String,
        toolName: String,
        arguments: [String: Any] = [:]
    ) async throws -> [String: Any] {
        let payload = try XPCJSON.data(from: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                proxy.callTool(connectionID: connectionID, toolName: toolName, arguments: payload) { data, _ in
                    do {
                        continuation.resume(returning: try XPCJSON.dictionary(from: data))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Sends an app command to the runtime and returns the decoded JSON payload.
    public func command(name: String, payload: [String: Any] = [:]) async throws -> [String: Any] {
        let request = try XPCJSON.data(from: payload)
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                proxy.command(name: name, payload: request) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    do {
                        continuation.resume(returning: try XPCJSON.dictionary(from: data))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Opens a runtime connection for the named agent client and returns the connection identifier.
    public func connectAgent(
        agent: String,
        clientName: String,
        clientVersion: String,
        initializeParams: [String: Any] = [:]
    ) async throws -> String {
        let payload = try XPCJSON.data(from: initializeParams)
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                proxy.connect(
                    agent: agent,
                    clientName: clientName,
                    clientVersion: clientVersion,
                    initializeParams: payload
                ) { connectionID, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let connectionID else {
                        continuation.resume(throwing: ManifoldXPCError.runtimeUnavailable)
                        return
                    }
                    continuation.resume(returning: connectionID)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Closes a previously opened runtime connection if the helper is reachable.
    public func disconnectAgent(connectionID: String) {
        guard let proxy = try? remoteProxy(errorHandler: { _ in }) else { return }
        proxy.disconnect(connectionID: connectionID)
    }

    private func remoteProxy(errorHandler: @escaping (Error) -> Void) throws -> ManifoldXPCProtocol {
        let connection = activeConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? ManifoldXPCProtocol else {
            throw ManifoldXPCError.runtimeUnavailable
        }
        return proxy
    }

    private func activeConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return connection
        }

        let connection = NSXPCConnection(machServiceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ManifoldXPCProtocol.self)
        connection.invalidationHandler = { [weak self] in
            self?.resetConnection()
        }
        connection.interruptionHandler = { [weak self] in
            self?.resetConnection()
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func resetConnection() {
        lock.lock()
        defer { lock.unlock() }
        connection = nil
    }
}
