// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct AccessDecision: Sendable, Codable {
    public let id: String
    public let connectionID: String
    public let agent: String
    public let toolName: String
    public let resourcePath: String?
    public let action: String
    public let allowed: Bool
    public let reason: String
    public let accessMode: String
    public let timestamp: Double
    public let policySnapshot: String?
    public let clientIdentity: String?
    public let intentSummary: String?
    public let intentDetails: String?

    public init(
        id: String = UUID().uuidString,
        connectionID: String,
        agent: String,
        toolName: String,
        resourcePath: String?,
        action: String,
        allowed: Bool,
        reason: String,
        accessMode: String,
        timestamp: Double = Date().timeIntervalSince1970,
        policySnapshot: String? = nil,
        clientIdentity: String? = nil,
        intentSummary: String? = nil,
        intentDetails: String? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.agent = agent
        self.toolName = toolName
        self.resourcePath = resourcePath
        self.action = action
        self.allowed = allowed
        self.reason = reason
        self.accessMode = accessMode
        self.timestamp = timestamp
        self.policySnapshot = policySnapshot
        self.clientIdentity = clientIdentity
        self.intentSummary = intentSummary
        self.intentDetails = intentDetails
    }
}
