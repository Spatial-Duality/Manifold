import Foundation

public struct ExposureRecord: Sendable, Codable {
    public let id: String
    public let connectionID: String
    public let agent: String
    public let toolName: String
    public let resourcePath: String?
    public let byteCount: Int
    public let contentHash: String
    public let exposureType: String
    public let timestamp: Double
    public let accessDecisionID: String

    public init(
        id: String = UUID().uuidString,
        connectionID: String,
        agent: String,
        toolName: String,
        resourcePath: String?,
        byteCount: Int,
        contentHash: String,
        exposureType: String,
        timestamp: Double = Date().timeIntervalSince1970,
        accessDecisionID: String
    ) {
        self.id = id
        self.connectionID = connectionID
        self.agent = agent
        self.toolName = toolName
        self.resourcePath = resourcePath
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.exposureType = exposureType
        self.timestamp = timestamp
        self.accessDecisionID = accessDecisionID
    }
}
