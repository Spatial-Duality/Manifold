import Foundation
import ManifoldKit
import os

private let runtimeLogger = Logger(subsystem: "com.spatialduality.manifold", category: "runtime")

public actor ManifoldRuntime {
    public nonisolated let db: DatabaseConnection
    public nonisolated let contentStore: ContentStore
    public nonisolated let auditStore: AuditStore
    public nonisolated let snapshotStore: SnapshotStore
    public nonisolated let leaseManager: WorkspaceLeaseManager
    public nonisolated let grantStore: GrantStore
    public nonisolated let emailStore: EmailStore
    public nonisolated let artifactIndex: ArtifactIndex
    public nonisolated let policyStore: PolicyStore
    public nonisolated let workBlockStore: WorkBlockStore
    public nonisolated let emailSyncEngine: EmailSyncEngine
    public nonisolated let approvalQueue: ApprovalQueue
    public nonisolated let exposureStore: ExposureStore

    private var bridges: [String: ManifoldBridge] = [:]

    public init(storeURL: URL? = nil) throws {
        let rootURL = storeURL ?? Self.defaultStoreURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let db = try DatabaseConnection(url: rootURL.appendingPathComponent("manifold.db"))
        let migrator = try DatabaseMigrator(db: db)
        try migrator.migrate()

        let contentStore = try ContentStore(rootURL: rootURL, db: db)
        let auditStore = try AuditStore(db: db)
        let snapshotStore = try SnapshotStore(db: db, contentStore: contentStore)
        let leaseManager = try WorkspaceLeaseManager(db: db, snapshotStore: snapshotStore)
        let grantStore = GrantStore(db: db)
        let emailStore = EmailStore(db: db)
        let artifactIndex = try ArtifactIndex(db: db)
        let policyStore = PolicyStore(db: db)
        let workBlockStore = WorkBlockStore(db: db)
        let emailSyncEngine = EmailSyncEngine(emailStore: emailStore)
        let approvalQueue = ApprovalQueue(db: db)
        let exposureStore = ExposureStore(db: db)

        self.db = db
        self.contentStore = contentStore
        self.auditStore = auditStore
        self.snapshotStore = snapshotStore
        self.leaseManager = leaseManager
        self.grantStore = grantStore
        self.emailStore = emailStore
        self.artifactIndex = artifactIndex
        self.policyStore = policyStore
        self.workBlockStore = workBlockStore
        self.emailSyncEngine = emailSyncEngine
        self.approvalQueue = approvalQueue
        self.exposureStore = exposureStore

        runtimeLogger.info("Initialized runtime at \(rootURL.path, privacy: .public)")
    }

    public func bridge(for connectionID: String, targetApp: TargetApp, version: String) -> ManifoldBridge {
        if let existing = bridges[connectionID] {
            return existing
        }

        let bridge = ManifoldBridge(
            db: db,
            auditStore: auditStore,
            contentStore: contentStore,
            grantStore: grantStore,
            emailStore: emailStore,
            snapshotStore: snapshotStore,
            artifactIndex: artifactIndex,
            policyStore: policyStore,
            workBlockStore: workBlockStore,
            approvalQueue: approvalQueue,
            exposureStore: exposureStore,
            targetApp: targetApp,
            serverName: "manifold",
            serverVersion: version,
            connectionID: connectionID
        )
        bridges[connectionID] = bridge
        return bridge
    }

    public func removeBridge(_ connectionID: String) {
        bridges.removeValue(forKey: connectionID)
    }

    public var activeBridgeCount: Int {
        bridges.count
    }

    public nonisolated static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manifold")
            .appendingPathComponent("store")
    }
}
