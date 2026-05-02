// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The four user-facing spaces in the main window.
enum LedgerDestination: String, Hashable, CaseIterable, Identifiable {
    case work
    case access
    case mail
    case rules

    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "work": self = .work
        case "access": self = .access
        case "mail": self = .mail
        case "rules": self = .rules
        default:
            return nil
        }
    }

    var keyboardIndex: Int {
        switch self {
        case .work: return 1
        case .access: return 2
        case .mail: return 3
        case .rules: return 4
        }
    }

    var title: String {
        switch self {
        case .work: return "Work"
        case .access: return "Access"
        case .mail: return "Mail"
        case .rules: return "Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .work: return "square.stack.3d.up"
        case .access: return "folder.badge.gearshape"
        case .mail: return "envelope"
        case .rules: return "slider.horizontal.3"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .work:
            return "Start a session to give Claude or Codex access to your shared folders and mailboxes. Approvals and activity will appear here."
        case .access:
            return "Nothing is shared until you share it. Add a folder to let an agent read from it inside a session."
        case .mail:
            return "Connect a mailbox to share mail with an agent. Subjects and senders are visible by default; message bodies require an explicit grant."
        case .rules:
            return "Rules control what agents can read, write, or redact. Suggested rules block secrets out of the box; add Mine rules for anything else."
        }
    }
}

/// Detail sections for the Access space. Owned by the Ledger window so the
/// sidebar and detail pane share one selection source.
enum AccessSection: String, Hashable, CaseIterable, Identifiable {
    case folders
    case files
    case session
    case history

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folders: return "Folders"
        case .files: return "Files"
        case .session: return "Session"
        case .history: return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .folders: return "folder.fill"
        case .files: return "doc.on.doc"
        case .session: return "play.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
