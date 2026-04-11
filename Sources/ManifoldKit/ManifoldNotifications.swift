import Foundation

/// Legacy notification names retained only for compatibility.
/// The app now refreshes state through XPC instead of cross-process notifications.
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

    /// Legacy no-op shim.
    public static func post(_ name: Notification.Name, userInfo: [String: String] = [:]) {
        _ = (name, userInfo)
    }

    /// Legacy no-op shim.
    @discardableResult
    public static func observe(_ name: Notification.Name, handler: @escaping @Sendable ([String: String]) -> Void) -> NSObjectProtocol {
        _ = (name, handler)
        return NSObject()
    }
}
