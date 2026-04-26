// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit
import ManifoldRuntime
import ManifoldXPC
import os

let agentLogger = Logger(subsystem: "com.spatialduality.manifold", category: "agent")
agentLogger.info("ManifoldAgent starting...")

let diagnostics = DiagnosticsRecorder(process: .agent)
diagnostics.recordAgentBoot()
diagnostics.record(.runtimeRegistrationAttempted)

// Mark cleanShutdown on graceful termination so the next app launch can tell
// the difference between a crash and a clean exit. SIGTERM is what launchd
// sends on a clean stop; SIGINT covers `^C` from a developer running it
// manually. SIGKILL cannot be caught — by design, a kill leaves the marker as
// `running`, which is exactly the signal the app needs to record an
// unexpected exit on next launch.
let cleanShutdownSources: [DispatchSourceSignal] = [SIGTERM, SIGINT].map { signo in
    signal(signo, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: signo, queue: .main)
    src.setEventHandler {
        diagnostics.recordAgentCleanShutdown()
        agentLogger.info("ManifoldAgent received signal \(signo, privacy: .public), exiting cleanly")
        exit(0)
    }
    src.resume()
    return src
}
_ = cleanShutdownSources  // keep alive

do {
    let runtime: ManifoldRuntime
    do {
        runtime = try ManifoldRuntime(
            storeURL: ManifoldRuntimeEnvironment.runtimeStoreURL()
        )
    } catch {
        diagnostics.record(.runtimeInitFailure(phase: .storeOpen))
        throw error
    }

    let service = ManifoldXPCService(runtime: runtime)
    let listener = NSXPCListener(
        machServiceName: ManifoldRuntimeEnvironment.xpcServiceName()
    )
    listener.delegate = service
    listener.resume()
    agentLogger.info("ManifoldAgent ready on \(ManifoldRuntimeEnvironment.xpcServiceName(), privacy: .public)")
    diagnostics.record(.runtimeRegistrationSucceeded)

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
