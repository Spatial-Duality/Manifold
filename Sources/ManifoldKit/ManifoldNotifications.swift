import Foundation

/// Shared notification names for IPC between the MCP server process and the Manifold app.
/// Uses DistributedNotificationCenter, which works across processes on the same machine.
public enum ManifoldNotification {
    /// Posted by MCP server when an agent connects.
    /// userInfo: ["agent": String]
    public static let agentConnected = Notification.Name("com.spatialduality.manifold.agentConnected")

    /// Posted by MCP server when an agent disconnects (process exit).
    /// userInfo: ["agent": String]
    public static let agentDisconnected = Notification.Name("com.spatialduality.manifold.agentDisconnected")

    /// Posted by MCP server when an agent tries to access an unapproved file.
    /// userInfo: ["path": String, "agent": String, "action": String]
    public static let accessDenied = Notification.Name("com.spatialduality.manifold.accessDenied")

    /// Posted by MCP server on every file read/write for live activity tracking.
    /// userInfo: ["path": String, "action": String, "agent": String]
    public static let fileAccessed = Notification.Name("com.spatialduality.manifold.fileAccessed")

    /// Posted by MCP server when audit data changes (new log entry written).
    /// App should refresh its activity feed.
    public static let dataChanged = Notification.Name("com.spatialduality.manifold.dataChanged")

    /// Post a notification to the distributed center (cross-process).
    public static func post(_ name: Notification.Name, userInfo: [String: String] = [:]) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: "manifold-mcp",
            userInfo: userInfo as [AnyHashable: Any],
            deliverImmediately: true
        )
    }

    /// Observe a notification from the distributed center.
    @discardableResult
    public static func observe(_ name: Notification.Name, handler: @escaping @Sendable ([String: String]) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: "manifold-mcp",
            queue: .main
        ) { notification in
            let info = notification.userInfo as? [String: String] ?? [:]
            handler(info)
        }
    }
}
