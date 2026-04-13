// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A request from an agent to access a resource outside its current policy.
/// Logged by ManifoldBridge when access is denied. Displayed in menu bar.
public struct AccessRequest: Sendable, Identifiable, Codable {
    public let id: String
    public let agent: TargetApp
    public let resourcePath: String
    public let resourceName: String
    public let requestedAt: String
    public var status: AccessRequestStatus

    public init(
        id: String = UUID().uuidString.prefix(12).lowercased().description,
        agent: TargetApp,
        resourcePath: String,
        resourceName: String,
        requestedAt: String = ISO8601DateFormatter.shared.string(from: Date()),
        status: AccessRequestStatus = .pending
    ) {
        self.id = id
        self.agent = agent
        self.resourcePath = resourcePath
        self.resourceName = resourceName
        self.requestedAt = requestedAt
        self.status = status
    }
}

public enum AccessRequestStatus: String, Sendable, Codable {
    case pending
    case approved
    case denied
    case expired
}
