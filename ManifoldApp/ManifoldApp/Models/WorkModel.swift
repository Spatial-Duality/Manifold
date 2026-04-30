// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// WorkModel — UI selection/composition model for the Work surface.
//
// Holds nothing the runtime owns. Views compose `SessionModel`,
// `SessionWorkbenchModel`, `GovernanceModel`, `ActivityModel`, and the
// pending-approval queue from `ManifoldStore`. WorkModel only tracks
// which session row and which inspector item the user has selected.
//
// Selection types are explicit (not just an ID string) so the inspector
// can render the right detail without rummaging through every store.

import Foundation
import ManifoldKit

/// Which row the user has currently picked in the Work session column.
enum WorkSessionSelection: Hashable, Sendable {
    /// The active live session (live runtime gateway).
    case active
    /// The default session (auto-started when startup mode == .defaultSession).
    case defaultSession
    /// A prepared session draft that hasn't been activated.
    case prepared
    /// A historical session (recently ended).
    case recent(sessionID: String)
}

/// Which item the inspector should render. Drives the right pane.
enum SelectedWorkItem: Hashable, Sendable {
    case none
    case session(WorkSessionSelection)
    case request(approvalID: String)
    case activityEvent(eventID: Int)
    case writeEvent(snapshotID: Int, filePath: String)
    case runtimeIssue
}

@Observable
@MainActor
final class WorkModel {
    /// Currently selected session in the left column.
    var sessionSelection: WorkSessionSelection = .active

    /// Currently selected inspector item.
    var inspectorSelection: SelectedWorkItem = .none

    /// The user's free-form filter text for the timeline.
    var timelineSearch: String = ""

    /// Which timeline filter is active.
    var timelineFilter: WorkTimelineFilter = .all

    /// Whether the runtime-issue inspector has its raw technical details
    /// expanded. Kept in the model so navigation back/forward preserves
    /// the choice.
    var runtimeIssueDisclosureExpanded: Bool = false
}

/// Top-level filter chips above the Work timeline.
enum WorkTimelineFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case approvals
    case writes
    case reads
    case search
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .approvals: return "Approvals"
        case .writes:    return "Writes"
        case .reads:     return "Reads"
        case .search:    return "Search"
        case .blocked:   return "Blocked"
        }
    }

    var systemImage: String {
        switch self {
        case .all:       return "list.bullet"
        case .approvals: return "hand.raised"
        case .writes:    return "pencil"
        case .reads:     return "eye"
        case .search:    return "magnifyingglass"
        case .blocked:   return "lock"
        }
    }

    /// Returns true if this audit entry should appear under the given filter.
    func includes(_ entry: AuditEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .approvals:
            // Approval-related actions: privacy/coverage/sensitivity warnings,
            // explicit "denied" actions, mcp connection events.
            return entry.action.contains("deny")
                || entry.action.contains("denied")
                || entry.action == AuditAction.sensitivityWarning.rawValue
                || entry.action == AuditAction.coverageWarning.rawValue
        case .writes:
            return entry.action.contains("write")
                || entry.action == AuditAction.fileModified.rawValue
                || entry.action == AuditAction.fileCreated.rawValue
                || entry.action == AuditAction.fileDeleted.rawValue
                || entry.action == AuditAction.restore.rawValue
        case .reads:
            return entry.action.contains("read")
        case .search:
            return entry.action.contains("search")
        case .blocked:
            return entry.action.contains("deny") || entry.action.contains("denied")
        }
    }
}

// MARK: - Per-session request detail override

/// How much intent the user wants Manifold to demand before answering a
/// request. Maps to backend `AccessRecordingLevel` per-agent.
enum SessionRequestDetail: String, CaseIterable, Identifiable, Sendable {
    case off
    case brief
    case detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:      return "Off"
        case .brief:    return "Brief"
        case .detailed: return "Detailed"
        }
    }

    var subtitle: String {
        switch self {
        case .off:      return "No intent fields required."
        case .brief:    return "Require a one-sentence summary."
        case .detailed: return "Require a summary plus richer context."
        }
    }

    /// Backend mapping — drives `AccessRecordingLevel` on the agent's
    /// access policy when the session is active.
    var backingLevel: AccessRecordingLevel {
        switch self {
        case .off:      return .lightweight
        case .brief:    return .summary
        case .detailed: return .detailed
        }
    }

    init(level: AccessRecordingLevel) {
        switch level {
        case .lightweight: self = .off
        case .summary:     self = .brief
        case .detailed:    self = .detailed
        }
    }
}
