// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldRuntime
import ManifoldXPC
import os

let agentLogger = Logger(subsystem: "com.spatialduality.manifold", category: "agent")
agentLogger.info("ManifoldAgent starting...")

do {
    let runtime = try ManifoldRuntime()
    let service = ManifoldXPCService(runtime: runtime)
    let listener = NSXPCListener(machServiceName: ManifoldXPCClient.serviceName)
    listener.delegate = service
    listener.resume()
    agentLogger.info("ManifoldAgent ready on \(ManifoldXPCClient.serviceName, privacy: .public)")

    Task {
        await runtime.bootstrap()
        do { _ = try await runtime.snapshotStore.pruneByAge(days: 30) }
        catch { agentLogger.warning("Snapshot pruning failed: \(error.localizedDescription, privacy: .public)") }
        do { _ = try await runtime.contentStore.garbageCollect() }
        catch { agentLogger.warning("Garbage collection failed: \(error.localizedDescription, privacy: .public)") }
        do { _ = try await runtime.approvalQueue.expire(olderThan: 30 * 60) }
        catch { agentLogger.warning("Approval queue cleanup failed: \(error.localizedDescription, privacy: .public)") }
    }

    RunLoop.main.run()
} catch {
    agentLogger.fault("ManifoldAgent failed: \(error.localizedDescription, privacy: .public)")
    exit(1)
}
