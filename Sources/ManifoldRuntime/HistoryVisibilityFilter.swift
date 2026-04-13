// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ManifoldKit

enum HistoryVisibilityFilter {
    static func relatedEmails(
        _ emails: [EmailMessageRecord],
        viewerPolicy: AgentAccessPolicy?,
        decisionResolver: @escaping @Sendable (EmailMessageRecord, AgentAccessPolicy) async throws -> EmailRuleDecision
    ) async throws -> [RelatedEmailContext] {
        guard let viewerPolicy else {
            return emails.map {
                RelatedEmailContext(id: $0.emailID, from: $0.sender, subject: $0.subject, date: $0.receivedAt)
            }
        }

        var summaries: [RelatedEmailContext] = []
        for email in emails {
            let decision = try await decisionResolver(email, viewerPolicy)
            if decision.allowed {
                summaries.append(
                    RelatedEmailContext(id: email.emailID, from: email.sender, subject: email.subject, date: email.receivedAt)
                )
            } else {
                summaries.append(
                    RelatedEmailContext(
                        id: email.emailID,
                        from: "Redacted",
                        subject: "Email hidden by current Manifold policy",
                        date: email.receivedAt,
                        isRedacted: true,
                        redactionReason: decision.message
                    )
                )
            }
        }
        return summaries
    }
}
