// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// PolicyModel+Session — Stage-6 session primitives exposed on PolicyModel.
//
// Additive over the existing PolicyModel. Internally `activeWorkBlock`
// remains the runtime-facing storage type; `activeSession` is the new
// UI vocabulary, computed lazily when called. During Phase 1 the two
// live side-by-side; in Phase 9 the legacy name is removed.

import Foundation
import ManifoldKit

extension PolicyModel {

    /// The live session (if any), derived from the active tracked work block.
    /// Returns nil when no session is running.
    var activeSession: SessionRecord? {
        guard let block = activeWorkBlock else { return nil }
        return SessionRecord(
            workBlock: block,
            expiresAt: nil,
            additions: [],
            removals: []
        )
    }

    /// Pending approval requests for the queue. Empty during Phase 1 —
    /// wired in Phase 5 when the Requests surface lands.
    var pendingRequests: [ApprovalRequest] { [] }

    /// Recent sessions, most recent first. Empty during Phase 1 — wired
    /// when SessionHistory ships in Phase 3.
    var recentSessions: [SessionHistoryEntry] { [] }

    /// Compute drift between a past session and current scope state.
    /// Phase-1 stub returns a clean drift; Phase 3 replaces with real
    /// comparison against PolicyStore + SnapshotStore.
    func drift(for entry: SessionHistoryEntry) -> SessionDrift {
        SessionDrift(
            historyEntry: entry,
            pathsChangedSinceEnded: [],
            pathsRevokedSinceEnded: [],
            newlyAddedSinceEnded: []
        )
    }
}
