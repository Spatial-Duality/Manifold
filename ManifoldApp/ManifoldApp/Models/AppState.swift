import SwiftUI
import Foundation

/// Central app state. Drives the UI.
@MainActor
class AppState: ObservableObject {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case sources = "Sources"
        case profiles = "Profiles"
        case activity = "Activity"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .sources: return "folder.badge.plus"
            case .profiles: return "person.2"
            case .activity: return "clock.arrow.circlepath"
            }
        }
    }

    enum AgentStatus {
        case inactive
        case active(agent: String, runID: String)
        case warning(message: String)
    }

    @Published var selectedSidebar: SidebarItem = .sources
    @Published var agentStatus: AgentStatus = .inactive
    @Published var sources: [SourceItem] = []
    @Published var activityEntries: [ActivityEntry] = []
    @Published var currentRunID: String?
    @Published var currentWorkspaceID: String?
    @Published var currentWorkspacePath: String?

    var menuBarIcon: String {
        switch agentStatus {
        case .inactive: return "circle"
        case .active: return "circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }

    var hasActiveRun: Bool {
        if case .active = agentStatus { return true }
        return false
    }

    // MARK: - Source Management

    func addFileSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select files or folders for agents to access"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let fileCount = isDir ? countFiles(in: url) : 1
            let source = SourceItem(
                id: UUID(),
                path: url.path,
                url: url,
                type: isDir ? .directory : .file,
                fileCount: fileCount,
                status: .synced,
                isSensitive: false
            )
            if !sources.contains(where: { $0.path == source.path }) {
                sources.append(source)
            }
        }
    }

    func removeSource(_ source: SourceItem) {
        sources.removeAll { $0.id == source.id }
    }

    // MARK: - Access Runs

    func grantAccess() {
        // Placeholder — will wire to WorkspaceLeaseManager
        let runID = "run-\(UUID().uuidString.prefix(8).lowercased())"
        let workspaceID = "ws-\(UUID().uuidString.prefix(8).lowercased())"
        currentRunID = runID
        currentWorkspaceID = workspaceID
        agentStatus = .active(agent: "Cowork", runID: runID)
    }

    func endAccess() {
        currentRunID = nil
        agentStatus = .inactive
    }

    func refreshAccess() {
        // End current run, re-sync, start new run
        endAccess()
        grantAccess()
    }

    // MARK: - Activity

    func addActivityEntry(_ entry: ActivityEntry) {
        activityEntries.insert(entry, at: 0)
    }

    func restoreEntry(_ entry: ActivityEntry) {
        let restoreEntry = ActivityEntry(
            id: UUID(),
            timestamp: Date(),
            runID: entry.runID,
            agent: "Manifold",
            filePath: entry.filePath,
            changeType: .restored,
            beforeHash: entry.afterHash,
            afterHash: entry.beforeHash,
            isSensitive: false
        )
        addActivityEntry(restoreEntry)
    }

    // MARK: - Helpers

    private func countFiles(in url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isFile { count += 1 }
        }
        return count
    }
}

// MARK: - Data Models

struct SourceItem: Identifiable {
    let id: UUID
    let path: String
    let url: URL
    let type: SourceType
    var fileCount: Int
    var status: SyncStatus
    var isSensitive: Bool

    enum SourceType {
        case file, directory, email
    }

    enum SyncStatus: String {
        case synced = "Synced"
        case syncing = "Syncing"
        case error = "Error"
    }

    var icon: String {
        switch type {
        case .file: return "doc"
        case .directory: return "folder"
        case .email: return "envelope"
        }
    }

    var displayName: String {
        if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
            return "~" + path.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)
        }
        return path
    }
}

struct ActivityEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let runID: String
    let agent: String
    let filePath: String
    let changeType: ChangeType
    let beforeHash: String?
    let afterHash: String?
    let isSensitive: Bool

    enum ChangeType: String {
        case created = "Created"
        case modified = "Modified"
        case deleted = "Deleted"
        case restored = "Restored"
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: timestamp).lowercased()
    }

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }
}
