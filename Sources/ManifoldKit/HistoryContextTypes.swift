import Foundation

public struct RelatedEmailContext: Sendable, Codable, Hashable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: String
    public let isRedacted: Bool
    public let redactionReason: String?

    public init(id: String, from: String, subject: String, date: String, isRedacted: Bool = false, redactionReason: String? = nil) {
        self.id = id
        self.from = from
        self.subject = subject
        self.date = date
        self.isRedacted = isRedacted
        self.redactionReason = redactionReason
    }
}

public struct FileHistoryContext: Sendable, Codable {
    public let filePath: String
    public let snapshots: [SnapshotRecord]
    public let relatedActivity: [AuditEntry]
    public let recentExposures: [ExposureRecord]
    public let relatedSessionIDs: [String]

    public init(
        filePath: String,
        snapshots: [SnapshotRecord],
        relatedActivity: [AuditEntry],
        recentExposures: [ExposureRecord],
        relatedSessionIDs: [String]
    ) {
        self.filePath = filePath
        self.snapshots = snapshots
        self.relatedActivity = relatedActivity
        self.recentExposures = recentExposures
        self.relatedSessionIDs = relatedSessionIDs
    }
}

public struct SessionContextDetail: Sendable, Codable {
    public let session: Session?
    public let grantID: String?
    public let entries: [AuditEntry]
    public let events: [SessionEvent]
    public let filePaths: [String]
    public let emails: [RelatedEmailContext]
    public let notes: [SessionSummaryRecord]

    public init(
        session: Session?,
        grantID: String?,
        entries: [AuditEntry],
        events: [SessionEvent],
        filePaths: [String],
        emails: [RelatedEmailContext],
        notes: [SessionSummaryRecord]
    ) {
        self.session = session
        self.grantID = grantID
        self.entries = entries
        self.events = events
        self.filePaths = filePaths
        self.emails = emails
        self.notes = notes
    }
}
