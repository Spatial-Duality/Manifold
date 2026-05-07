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

    /// Posted on the main NotificationCenter when the underlying NSXPC
    /// connection invalidates or is interrupted. Lets app-side state
    /// react to disconnects in <100ms instead of waiting for the next
    /// 5-second ping. The payload's `userInfo["connected"]` is `false`
    /// today (we don't have a connect-event from the underlying API).
    public static let connectionStateChangedNotification =
        Notification.Name("manifold.xpc.connectionStateChanged")

    private let requestTimeout: TimeInterval = 12
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    /// Creates a client that lazily connects to the runtime helper.
    public init() {}

    /// Calls a governed MCP-style tool on behalf of an existing runtime connection.
    public func callTool(
        connectionID: String,
        requestID: String = ManifoldRequestID().rawValue,
        toolName: String,
        arguments: [String: Any] = [:]
    ) async throws -> [String: Any] {
        let payload = try XPCJSON.data(from: arguments)
        return try await withCheckedThrowingContinuation { continuation in
            let reply = SingleShotThrowingContinuation<[String: Any]>(continuation)
            let timeout = timeoutWorkItem(operation: "tool \(toolName)", reply: reply)
            do {
                let proxy = try remoteProxy { error in
                    if reply.resume(throwing: error) { timeout.cancel() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
                proxy.callTool(connectionID: connectionID, requestID: requestID, toolName: toolName, arguments: payload) { data, _ in
                    do {
                        if reply.resume(returning: try XPCJSON.dictionary(from: data)) { timeout.cancel() }
                    } catch {
                        if reply.resume(throwing: error) { timeout.cancel() }
                    }
                }
            } catch {
                if reply.resume(throwing: error) { timeout.cancel() }
            }
        }
    }

    /// Sends an app command to the runtime and returns the decoded JSON payload.
    public func command(
        requestID: String = ManifoldRequestID().rawValue,
        name: String,
        payload: [String: Any] = [:]
    ) async throws -> [String: Any] {
        let request = try XPCJSON.data(from: payload)
        return try await withCheckedThrowingContinuation { continuation in
            let reply = SingleShotThrowingContinuation<[String: Any]>(continuation)
            let timeout = timeoutWorkItem(operation: "command \(name)", reply: reply)
            do {
                let proxy = try remoteProxy { error in
                    if reply.resume(throwing: error) { timeout.cancel() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
                proxy.command(requestID: requestID, name: name, payload: request) { data, error in
                    if let error {
                        if reply.resume(throwing: error) { timeout.cancel() }
                        return
                    }
                    do {
                        if reply.resume(returning: try XPCJSON.dictionary(from: data)) { timeout.cancel() }
                    } catch {
                        if reply.resume(throwing: error) { timeout.cancel() }
                    }
                }
            } catch {
                if reply.resume(throwing: error) { timeout.cancel() }
            }
        }
    }

    /// Opens a runtime connection for the named agent client and returns the connection identifier.
    public func connectAgent(
        requestID: String = ManifoldRequestID().rawValue,
        agent: String,
        clientName: String,
        clientVersion: String,
        initializeParams: [String: Any] = [:]
    ) async throws -> String {
        let payload = try XPCJSON.data(from: initializeParams)
        return try await withCheckedThrowingContinuation { continuation in
            let reply = SingleShotThrowingContinuation<String>(continuation)
            let timeout = timeoutWorkItem(operation: "connect", reply: reply)
            do {
                let proxy = try remoteProxy { error in
                    if reply.resume(throwing: error) { timeout.cancel() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
                proxy.connect(
                    requestID: requestID,
                    agent: agent,
                    clientName: clientName,
                    clientVersion: clientVersion,
                    initializeParams: payload
                ) { connectionID, error in
                    if let error {
                        if reply.resume(throwing: error) { timeout.cancel() }
                        return
                    }
                    guard let connectionID else {
                        if reply.resume(throwing: ManifoldXPCError.runtimeUnavailable) { timeout.cancel() }
                        return
                    }
                    if reply.resume(returning: connectionID) { timeout.cancel() }
                }
            } catch {
                if reply.resume(throwing: error) { timeout.cancel() }
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

    private func timeoutWorkItem<Value>(
        operation: String,
        reply: SingleShotThrowingContinuation<Value>
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            _ = reply.resume(throwing: ManifoldXPCError.timeout(operation))
        }
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
        connection = nil
        lock.unlock()
        // Post on the main NotificationCenter so SwiftUI observers can
        // react synchronously on the next main-thread tick. The XPC
        // callbacks fire on a private queue, so we hop to main first.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.connectionStateChangedNotification,
                object: nil,
                userInfo: ["connected": false]
            )
        }
    }
}
