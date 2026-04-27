// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// Capability handle MCP tools.
///
/// `create_value_handle` mints a handle for sensitive data with allowed
/// sinks; `check_capability_flow` evaluates a handle's flow into a sink and
/// applies the Rule-of-Two (sensitive + untrusted + state-changing → block).
extension ManifoldBridge {
    public func createValueHandle(
        origin: String,
        sensitivity: String,
        trustLevel: String,
        allowedSinks: [String]
    ) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "create_value_handle", action: "capability", resourcePath: origin)
        guard let capabilityHandleStore else {
            return "Capability handle store unavailable."
        }
        let grantID = grantID(in: context)
        let lineage = sourceIDs(in: context).sorted().map { LineageRef(kind: "source", id: $0) }
        let handle = try await capabilityHandleStore.save(
            ValueHandle(
                origin: origin,
                sensitivity: sensitivity,
                trustLevel: trustLevel,
                allowedSinks: allowedSinks,
                grantID: grantID,
                lineage: lineage
            )
        )
        try await ledgerStore?.append(
            entryType: .valueHandle,
            subjectTable: "value_handles",
            subjectID: handle.handleID,
            payload: Self.canonicalJSON(handle),
            metadata: ["origin": origin, "sensitivity": sensitivity, "trust_level": trustLevel]
        )
        let text = "Created value handle \(handle.handleID) for \(origin). Allowed sinks: \(allowedSinks.joined(separator: ", "))."
        await recordExposure(toolName: "create_value_handle", resourcePath: origin, text: text, exposureType: "capability", decisionID: decisionID)
        return text
    }

    public func checkCapabilityFlow(
        handleID: String,
        sink: String,
        untrustedInput: Bool = false,
        stateChangingAction: Bool = false
    ) async throws -> String {
        let (context, decisionID) = try await resolveAccessForTool(toolName: "check_capability_flow", action: "capability", resourcePath: handleID)
        guard let capabilityHandleStore else {
            return "Capability handle store unavailable."
        }
        let result: CapabilityFlowResult
        if let handle = try await capabilityHandleStore.handle(id: handleID),
           canAccessValueHandle(handle, in: context) {
            result = await capabilityHandleStore.checkFlow(
                handle: handle,
                sink: sink,
                untrustedInput: untrustedInput,
                stateChangingAction: stateChangingAction
            )
        } else {
            result = CapabilityFlowResult(
                allowed: false,
                reason: "Capability handle is unavailable in the current session scope.",
                handleID: handleID,
                sink: sink
            )
        }
        let text = Self.canonicalJSON(result)
        await recordExposure(toolName: "check_capability_flow", resourcePath: handleID, text: text, exposureType: "capability", decisionID: decisionID)
        return text
    }
}
