// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ManifoldXPCError: LocalizedError {
    case runtimeUnavailable
    case malformedReply
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Unable to connect to the Manifold runtime."
        case .malformedReply:
            return "The Manifold runtime returned an unexpected response."
        case .invalidPayload:
            return "The Manifold runtime received invalid JSON."
        }
    }
}

public struct AgentCommandPayload: Codable, Sendable {
    public let agent: String
    public init(agent: String) { self.agent = agent }
}

public struct LimitPayload: Codable, Sendable {
    public let limit: Int
    public init(limit: Int) { self.limit = limit }
}

public struct RequestIDPayload: Codable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

public struct RuleMatchPreview: Codable, Sendable, Hashable {
    public struct Sample: Codable, Sendable, Hashable {
        public let identifier: String
        public let label: String

        public init(identifier: String, label: String) {
            self.identifier = identifier
            self.label = label
        }
    }

    public let ruleID: String
    public let fileMatches: Int
    public let emailMatches: Int
    public let agentMatches: Int
    public let sample: [Sample]

    public init(ruleID: String, fileMatches: Int, emailMatches: Int, agentMatches: Int, sample: [Sample]) {
        self.ruleID = ruleID
        self.fileMatches = fileMatches
        self.emailMatches = emailMatches
        self.agentMatches = agentMatches
        self.sample = sample
    }

    public var totalMatches: Int { fileMatches + emailMatches + agentMatches }
}

public struct RestoreSnapshotResult: Codable, Sendable {
    public let status: String
    public let message: String?

    public init(status: String, message: String? = nil) {
        self.status = status
        self.message = message
    }
}

public enum XPCJSON {
    public static func data(from object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ManifoldXPCError.invalidPayload
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func dictionary(from data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManifoldXPCError.malformedReply
        }
        return dictionary
    }

    public static func array(from data: Data) throws -> [Any] {
        guard !data.isEmpty else { return [] }
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ManifoldXPCError.malformedReply
        }
        return array
    }

    public static func nsError(from error: Error) -> NSError {
        if let nsError = error as NSError? {
            return nsError
        }
        return NSError(
            domain: "com.spatialduality.manifold.xpc",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }

    public static func data<T: Encodable>(from value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func object<T: Encodable>(from value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let data: Data
        if JSONSerialization.isValidJSONObject(object) {
            data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } else {
            // Scalar value (Bool, Int, String) — not a valid top-level JSON object.
            // Wrap in array so JSONSerialization can handle it, then decode the first element.
            let wrapped = try JSONSerialization.data(withJSONObject: [object])
            let array = try JSONDecoder().decode([T].self, from: wrapped)
            guard let first = array.first else { throw ManifoldXPCError.malformedReply }
            return first
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
