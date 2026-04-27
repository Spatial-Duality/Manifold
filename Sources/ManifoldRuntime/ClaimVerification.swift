// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

/// One claimed action parsed from `verify_claimed_actions` input.
///
/// `ClaimedAction` separates structured input (tool_name + resource_path or
/// content_hash, which can be `supported`) from free-text input (which can at
/// best be `ambiguous`).
struct ClaimedAction {
    let text: String
    let toolName: String?
    let resourcePath: String?
    let contentHash: String?
    let isStructured: Bool
}

/// Pure functions for parsing claims and grading them against exposure evidence.
///
/// Extracted from `ManifoldBridge.verifyClaimedActions` so the parsing and
/// grading logic can evolve independently of the bridge's IO and state.
/// Nothing here touches the bridge's actor state.
enum ClaimEvidence {
    /// Parses a JSON payload into individual `ClaimedAction`s. Falls back to
    /// returning a single unstructured claim when the input is plain text.
    static func parse(json: String) -> [ClaimedAction] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [ClaimedAction(text: trimmed, toolName: nil, resourcePath: nil, contentHash: nil, isStructured: false)]
        }
        let values: [Any]
        if let array = object as? [Any] {
            values = array
        } else {
            values = [object]
        }
        return values.compactMap { value in
            if let string = value as? String {
                return ClaimedAction(text: string, toolName: nil, resourcePath: nil, contentHash: nil, isStructured: false)
            }
            guard let dictionary = value as? [String: Any] else { return nil }
            let toolName = stringValue(dictionary["tool_name"]) ?? stringValue(dictionary["tool"])
            let resourcePath = stringValue(dictionary["resource_path"]) ?? stringValue(dictionary["path"])
            let contentHash = stringValue(dictionary["content_hash"]) ?? stringValue(dictionary["hash"])
            let text = stringValue(dictionary["claim"]) ?? [
                toolName.map { "tool=\($0)" },
                resourcePath.map { "resource=\($0)" },
                contentHash.map { "hash=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
            return ClaimedAction(text: text.isEmpty ? "\(dictionary)" : text, toolName: toolName, resourcePath: resourcePath, contentHash: contentHash, isStructured: true)
        }
    }

    /// Grades a single claim against scoped exposure records. Returns the
    /// status/evidence dictionary persisted on `FabricationFinding`.
    static func evidence(for claim: ClaimedAction, exposures: [ExposureRecord]) -> [String: String] {
        if let contentHash = claim.contentHash, !contentHash.isEmpty {
            if let match = exposures.first(where: { exposure in
                exposure.contentHash == contentHash
                    && (claim.toolName.map { $0 == exposure.toolName } ?? true)
                    && (claim.resourcePath.map { $0 == exposure.resourcePath } ?? true)
            }) {
                return ["status": "supported", "evidence": "exposure \(match.id) matched content hash \(String(contentHash.prefix(12)))"]
            }
            return ["status": "unverified", "evidence": "no scoped exposure matched content hash \(String(contentHash.prefix(12)))"]
        }

        if let toolName = claim.toolName,
           let resourcePath = claim.resourcePath,
           let match = exposures.first(where: { $0.toolName == toolName && $0.resourcePath == resourcePath }) {
            return ["status": "supported", "evidence": "exposure \(match.id) matched \(match.toolName) \(match.resourcePath ?? "-")"]
        }
        if claim.toolName != nil, claim.resourcePath != nil {
            return ["status": "unverified", "evidence": "no scoped exposure matched tool_name + resource_path"]
        }

        let claimLower = claim.text.lowercased()
        if let match = exposures.first(where: { exposure in
            claimLower.contains(exposure.toolName.lowercased())
                || exposure.resourcePath.map { claimLower.contains($0.lowercased()) } == true
                || claimLower.contains(exposure.contentHash.lowercased())
        }) {
            return ["status": "ambiguous", "evidence": "claim text only loosely matched scoped exposure \(match.id); provide tool_name + resource_path or content_hash for support"]
        }

        if !claim.isStructured || claim.toolName != nil || claim.resourcePath != nil {
            return ["status": "ambiguous", "evidence": "structured tool_name + resource_path or content_hash is required for support"]
        }

        return ["status": "unverified", "evidence": "no matching scoped exposure"]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}
