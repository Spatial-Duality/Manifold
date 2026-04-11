import Foundation
import ManifoldKit

struct AgentRuntimeContext: Sendable {
    let connectionID: String
    let targetApp: TargetApp
    let profileID: String
    let serverName: String
    let serverVersion: String
    let transport: String
    let connectedAt: String
    let serverPID: String
    let serverProcessName: String
    let timeZoneIdentifier: String
    let localeIdentifier: String
    let operatingSystemVersion: String

    var protocolVersion: String?
    var clientName: String?
    var clientVersion: String?
    var providerHint: String?
    var modelHint: String?
    var initializeKeys: [String]
    var capabilityKeys: [String]

    init(
        connectionID: String? = nil,
        targetApp: TargetApp,
        profileID: String,
        serverName: String,
        serverVersion: String,
        transport: String = "stdio"
    ) {
        self.connectionID = connectionID ?? "conn-\(UUID().uuidString.prefix(12).lowercased())"
        self.targetApp = targetApp
        self.profileID = profileID
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.transport = transport
        self.connectedAt = ISO8601DateFormatter.shared.string(from: Date())
        self.serverPID = "\(ProcessInfo.processInfo.processIdentifier)"
        self.serverProcessName = ProcessInfo.processInfo.processName
        self.timeZoneIdentifier = TimeZone.current.identifier
        self.localeIdentifier = Locale.current.identifier
        self.operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.protocolVersion = nil
        self.clientName = nil
        self.clientVersion = nil
        self.providerHint = Self.firstNonEmptyEnvironmentValue(
            keys: ["MANIFOLD_PROVIDER_HINT", "MODEL_PROVIDER", "PROVIDER"]
        )
        self.modelHint = Self.firstNonEmptyEnvironmentValue(
            keys: ["MANIFOLD_MODEL_HINT", "MODEL_NAME", "MODEL", "CODEX_MODEL", "CLAUDE_MODEL"]
        )
        self.initializeKeys = []
        self.capabilityKeys = []
    }

    mutating func mergeInitializeParams(_ params: [String: Any]) {
        initializeKeys = params.keys.sorted()
        protocolVersion = protocolVersion ?? Self.stringValue(in: params, path: ["protocolVersion"])

        if let clientInfo = params["clientInfo"] as? [String: Any] {
            clientName = clientName ?? Self.stringValue(in: clientInfo, path: ["name"])
            clientVersion = clientVersion ?? Self.stringValue(in: clientInfo, path: ["version"])
        }

        if let capabilities = params["capabilities"] as? [String: Any] {
            capabilityKeys = capabilities.keys.sorted()
        }

        providerHint = providerHint ?? Self.firstStringValue(
            in: params,
            candidatePaths: [
                ["provider"], ["providerName"], ["provider_name"], ["vendor"],
                ["metadata", "provider"], ["metadata", "providerName"], ["metadata", "vendor"],
                ["clientInfo", "provider"], ["clientInfo", "vendor"],
            ]
        )

        modelHint = modelHint ?? Self.firstStringValue(
            in: params,
            candidatePaths: [
                ["model"], ["modelName"], ["model_name"],
                ["metadata", "model"], ["metadata", "modelName"], ["metadata", "model_name"],
                ["clientInfo", "model"], ["clientInfo", "modelName"],
            ]
        )
    }

    var connectionMetadata: [String: String] {
        var metadata: [String: String] = [
            "connection_id": connectionID,
            "target_app": targetApp.rawValue,
            "profile_id": profileID,
            "server_name": serverName,
            "server_version": serverVersion,
            "transport": transport,
            "connected_at": connectedAt,
            "server_pid": serverPID,
            "server_process_name": serverProcessName,
            "time_zone": timeZoneIdentifier,
            "locale": localeIdentifier,
            "os_version": operatingSystemVersion,
        ]
        if let protocolVersion {
            metadata["protocol_version"] = protocolVersion
        }
        if let clientName {
            metadata["client_name"] = clientName
        }
        if let clientVersion {
            metadata["client_version"] = clientVersion
        }
        if let providerHint {
            metadata["provider_hint"] = providerHint
        }
        if let modelHint {
            metadata["model_hint"] = modelHint
        }
        if !initializeKeys.isEmpty {
            metadata["initialize_keys"] = initializeKeys.joined(separator: ",")
        }
        if !capabilityKeys.isEmpty {
            metadata["capability_keys"] = capabilityKeys.joined(separator: ",")
        }
        return metadata
    }

    var eventContextMetadata: [String: String] {
        var metadata: [String: String] = [
            "connection_id": connectionID,
            "target_app": targetApp.rawValue,
            "profile_id": profileID,
            "server_version": serverVersion,
        ]
        if let clientName {
            metadata["client_name"] = clientName
        }
        if let clientVersion {
            metadata["client_version"] = clientVersion
        }
        if let providerHint {
            metadata["provider_hint"] = providerHint
        }
        if let modelHint {
            metadata["model_hint"] = modelHint
        }
        return metadata
    }

    private static func stringValue(in dictionary: [String: Any], path: [String]) -> String? {
        guard !path.isEmpty else { return nil }
        var current: Any = dictionary
        for key in path {
            guard let nested = current as? [String: Any], let next = nested[key] else {
                return nil
            }
            current = next
        }
        if let string = current as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func firstStringValue(in dictionary: [String: Any], candidatePaths: [[String]]) -> String? {
        for path in candidatePaths {
            if let value = stringValue(in: dictionary, path: path) {
                return value
            }
        }
        return nil
    }

    private static func firstNonEmptyEnvironmentValue(keys: [String]) -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in keys {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
