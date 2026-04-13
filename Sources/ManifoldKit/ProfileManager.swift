// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Manages named access profiles (Work, Research, Code, Custom).
/// Each profile = set of source paths + email filter overrides.
/// Global email rules always apply. Profiles can add per-profile relaxations.
public struct ProfileManager: Sendable {
    private let profilesURL: URL

    public init(baseURL: URL) {
        self.profilesURL = baseURL.appendingPathComponent("profiles")
        try? FileManager.default.createDirectory(at: profilesURL, withIntermediateDirectories: true)
    }

    /// Load all saved profiles.
    public func allProfiles() -> [NamedProfile] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let profile = try? JSONDecoder().decode(NamedProfile.self, from: data) else { return nil }
                return profile
            }
            .sorted { $0.name < $1.name }
    }

    /// Save a profile.
    public func save(_ profile: NamedProfile) throws {
        let url = profilesURL.appendingPathComponent("\(profile.id).json")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: url, options: .atomic)
    }

    /// Delete a profile.
    public func delete(id: String) throws {
        let url = profilesURL.appendingPathComponent("\(id).json")
        try FileManager.default.removeItem(at: url)
    }

    /// Load a profile by ID.
    public func load(id: String) -> NamedProfile? {
        let url = profilesURL.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NamedProfile.self, from: data)
    }

    /// Create default suggested presets if none exist.
    public func seedDefaults(availableSources: [String]) -> [NamedProfile] {
        let existing = allProfiles()
        guard existing.isEmpty else { return existing }

        let work = NamedProfile(
            id: "work",
            name: "Work",
            icon: "briefcase",
            sourcePaths: availableSources,
            includeEmails: true,
            emailDomainOverrides: [:]
        )

        let code = NamedProfile(
            id: "code",
            name: "Code",
            icon: "terminal",
            sourcePaths: availableSources.filter {
                $0.contains("Projects") || $0.contains("src") || $0.contains("Developer")
            },
            includeEmails: false,
            emailDomainOverrides: [:]
        )

        let research = NamedProfile(
            id: "research",
            name: "Research",
            icon: "book",
            sourcePaths: availableSources,
            includeEmails: true,
            emailDomainOverrides: [:]
        )

        for profile in [work, code, research] {
            try? save(profile)
        }

        return [work, code, research]
    }
}

public struct NamedProfile: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var icon: String
    public var sourcePaths: [String]
    public var includeEmails: Bool
    public var emailDomainOverrides: [String: Bool] // domain -> force include (true) or force hide (false)

    public init(id: String, name: String, icon: String, sourcePaths: [String], includeEmails: Bool, emailDomainOverrides: [String: Bool]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sourcePaths = sourcePaths
        self.includeEmails = includeEmails
        self.emailDomainOverrides = emailDomainOverrides
    }
}
