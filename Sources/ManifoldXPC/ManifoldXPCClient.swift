// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public final class ManifoldXPCClient: @unchecked Sendable {
    public static let serviceName = "com.spatialduality.manifold.runtime"

    private let lock = NSLock()
    private var connection: NSXPCConnection?

    public init() {}

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
