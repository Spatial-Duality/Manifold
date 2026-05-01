// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct LocalAuthConfig: Sendable, Equatable {
    public let microsoftClientID: String?
    public let microsoftRedirectURI: String?
    public let microsoftCallbackScheme: String?
    public let googleClientID: String?
    public let googleRedirectURI: String?

    public init(
        microsoftClientID: String? = nil,
        microsoftRedirectURI: String? = nil,
        microsoftCallbackScheme: String? = nil,
        googleClientID: String? = nil,
        googleRedirectURI: String? = nil
    ) {
        self.microsoftClientID = microsoftClientID?.nilIfBlank
        self.microsoftRedirectURI = microsoftRedirectURI?.nilIfBlank
        self.microsoftCallbackScheme = microsoftCallbackScheme?.nilIfBlank
        self.googleClientID = googleClientID?.nilIfBlank
        self.googleRedirectURI = googleRedirectURI?.nilIfBlank
    }

    public var isMicrosoftOAuthConfigured: Bool {
        microsoftClientID != nil && microsoftCallbackScheme != nil
    }

    public static func load(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> LocalAuthConfig {
        var values: [String: String] = [:]

        if let url = bundle.url(forResource: "ManifoldLocalAuthConfig", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (key, value) in plist {
                if let string = value as? String {
                    values[key] = string
                }
            }
        }

        let env = ProcessInfo.processInfo.environment
        let environmentKeys: [String: [String]] = [
            "MicrosoftClientID": ["MANIFOLD_MICROSOFT_CLIENT_ID", "MicrosoftClientID"],
            "MicrosoftRedirectURI": ["MANIFOLD_MICROSOFT_REDIRECT_URI", "MicrosoftRedirectURI"],
            "MicrosoftCallbackScheme": ["MANIFOLD_MICROSOFT_CALLBACK_SCHEME", "MicrosoftCallbackScheme"],
            "GoogleClientID": ["MANIFOLD_GOOGLE_CLIENT_ID", "GoogleClientID"],
            "GoogleRedirectURI": ["MANIFOLD_GOOGLE_REDIRECT_URI", "GoogleRedirectURI"],
        ]
        for (key, aliases) in environmentKeys {
            if let value = aliases.compactMap({ env[$0] }).first {
                values[key] = value
            }
        }

        return LocalAuthConfig(
            microsoftClientID: values["MicrosoftClientID"],
            microsoftRedirectURI: values["MicrosoftRedirectURI"],
            microsoftCallbackScheme: values["MicrosoftCallbackScheme"],
            googleClientID: values["GoogleClientID"],
            googleRedirectURI: values["GoogleRedirectURI"]
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
