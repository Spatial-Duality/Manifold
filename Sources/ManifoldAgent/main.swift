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
        _ = try? await runtime.snapshotStore.pruneByAge(days: 30)
        _ = try? await runtime.contentStore.garbageCollect()
        _ = try? await runtime.approvalQueue.expire(olderThan: 30 * 60)
    }

    RunLoop.main.run()
} catch {
    agentLogger.fault("ManifoldAgent failed: \(error.localizedDescription, privacy: .public)")
    exit(1)
}
