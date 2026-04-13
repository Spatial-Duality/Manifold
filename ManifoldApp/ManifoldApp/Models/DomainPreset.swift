// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct DomainPreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let suggestedSources: [String]
    let emailSensitivity: EmailSensitivity
    let summaryFraming: String

    enum EmailSensitivity: String, Sendable {
        case strict    // Hide most emails, only share explicitly selected
        case moderate  // Auto-hide sensitive (banking, health), share rest
        case open      // Share most emails, only hide 2FA and banking
    }

    static let presets: [DomainPreset] = [
        DomainPreset(
            id: "legal",
            name: "Legal Review",
            icon: "building.columns",
            description: "Review contracts, filings, and legal correspondence with strict email filtering.",
            suggestedSources: ["Documents/Legal", "Documents/Contracts"],
            emailSensitivity: .strict,
            summaryFraming: "Legal review session"
        ),
        DomainPreset(
            id: "design",
            name: "Design Brief",
            icon: "paintbrush",
            description: "Share design assets and creative briefs. Moderate email sharing for client feedback.",
            suggestedSources: ["Documents/Design", "Desktop"],
            emailSensitivity: .moderate,
            summaryFraming: "Design session"
        ),
        DomainPreset(
            id: "marketing",
            name: "Marketing Campaign",
            icon: "megaphone",
            description: "Campaign docs, copy, analytics. Open email sharing for campaign threads.",
            suggestedSources: ["Documents/Marketing", "Documents/Campaigns"],
            emailSensitivity: .open,
            summaryFraming: "Marketing session"
        ),
        DomainPreset(
            id: "finance",
            name: "Finance Analysis",
            icon: "chart.bar.doc.horizontal",
            description: "Financial reports and analysis. Strict email filtering to protect sensitive data.",
            suggestedSources: ["Documents/Finance", "Documents/Reports"],
            emailSensitivity: .strict,
            summaryFraming: "Finance review session"
        ),
        DomainPreset(
            id: "research",
            name: "Research",
            icon: "book",
            description: "Academic papers, notes, and research materials. Moderate email for collaboration.",
            suggestedSources: ["Documents/Research", "Documents/Papers"],
            emailSensitivity: .moderate,
            summaryFraming: "Research session"
        ),
        DomainPreset(
            id: "general",
            name: "General",
            icon: "folder",
            description: "No specific domain. Default settings for any type of work.",
            suggestedSources: [],
            emailSensitivity: .moderate,
            summaryFraming: "Work session"
        ),
    ]
}
