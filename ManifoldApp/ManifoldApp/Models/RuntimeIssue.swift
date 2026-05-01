// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// RuntimeIssue — typed model of runtime/connection problems.
//
// Replaces ad-hoc string-grep error routing in WorkView with a typed
// classifier that maps low-level signals (ping failure, error strings,
// XPC invalidation events) into a single enum that drives both copy
// and recovery action. One source of truth; no more accidental matches
// on unrelated errors that contain "stale" or "reconnect."
//
// The classifier still tolerates string-shaped errors today because
// those are what the runtime currently returns. As the agent migrates
// to typed error codes, callers swap one branch at a time without
// touching the UI surface.

import Foundation

enum RuntimeIssueRecoveryAction: Sendable {
    case retry
    case restart
    case reconnect
}

enum RuntimeIssue: Sendable, Equatable {
    case runtimeUnavailable(detail: String)
    case staleHelper(detail: String)
    case helperError(detail: String)

    var title: String {
        switch self {
        case .runtimeUnavailable: return "Runtime unavailable"
        case .staleHelper:        return "Agent helper out of date"
        case .helperError:        return "Runtime needs restart"
        }
    }

    var detail: String {
        switch self {
        case .runtimeUnavailable(let d), .staleHelper(let d), .helperError(let d):
            return d
        }
    }

    var recoveryAction: RuntimeIssueRecoveryAction {
        switch self {
        case .runtimeUnavailable: return .retry
        case .staleHelper:        return .reconnect
        case .helperError:        return .restart
        }
    }

    var primaryActionLabel: String {
        switch recoveryAction {
        case .retry:     return "Retry"
        case .restart:   return "Restart runtime"
        case .reconnect: return "Reconnect agents"
        }
    }
}

/// Pure classifier — no side effects. Maps the available app-side
/// signals into a single typed issue, or `nil` if everything is healthy.
///
/// Today's signals are mostly stringly-typed (`runtimeLaunchError`,
/// `lastError`) because that's what the agent layer surfaces. The
/// classifier centralizes the matching so when the agent grows typed
/// error codes, only this function changes — every consumer keeps
/// reading the same enum.
enum RuntimeIssueClassifier {
    static func classify(
        isRuntimeConnected: Bool,
        runtimeLaunchError: String?,
        lastError: String?
    ) -> RuntimeIssue? {
        let combined = ((runtimeLaunchError ?? "") + " " + (lastError ?? "")).lowercased()
        // Match whole tokens to avoid false positives on words like
        // "reconnected" or substrings inside unrelated errors. Word
        // boundaries: any non-letter neighbour counts.
        let isStale = containsToken(combined, "stale") || containsToken(combined, "reconnect")

        if isStale {
            return .staleHelper(detail: runtimeLaunchError ?? lastError
                ?? "Claude or Codex is running an older copy of the Manifold helper. Reconnecting will relaunch it.")
        }
        if !isRuntimeConnected {
            return .runtimeUnavailable(detail: runtimeLaunchError ?? lastError
                ?? "Manifold can't reach the runtime right now.")
        }
        if let helperError = lastError, !helperError.isEmpty {
            return .helperError(detail: helperError)
        }
        return nil
    }

    /// Whole-word match. Avoids classifying "reconnected to mailbox" as
    /// a stale-helper signal just because the substring "reconnect" is
    /// present inside a larger word.
    private static func containsToken(_ haystack: String, _ token: String) -> Bool {
        guard let range = haystack.range(of: token) else { return false }
        let before = range.lowerBound > haystack.startIndex
            ? haystack[haystack.index(before: range.lowerBound)]
            : nil
        let after = range.upperBound < haystack.endIndex
            ? haystack[range.upperBound]
            : nil
        let isLetterBoundaryStart = before.map { !$0.isLetter } ?? true
        let isLetterBoundaryEnd = after.map { !$0.isLetter } ?? true
        return isLetterBoundaryStart && isLetterBoundaryEnd
    }
}

/// Notification posted by `ManifoldXPCClient` when its connection is
/// invalidated or interrupted, so app-level state can react in <100ms
/// instead of waiting for the next 5s ping. The current state is in
/// `userInfo["connected"]` as `Bool`.
extension Notification.Name {
    static let manifoldXPCConnectionStateChanged = Notification.Name("manifold.xpc.connectionStateChanged")
}
