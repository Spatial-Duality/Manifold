// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Security

public struct MicrosoftOAuthAuthorizationRequest: Sendable, Equatable {
    public let authorizationURL: URL
    public let callbackScheme: String
    public let state: String
    public let codeVerifier: String
    public let codeChallenge: String
    public let redirectURI: String

    public init(
        authorizationURL: URL,
        callbackScheme: String,
        state: String,
        codeVerifier: String,
        codeChallenge: String,
        redirectURI: String
    ) {
        self.authorizationURL = authorizationURL
        self.callbackScheme = callbackScheme
        self.state = state
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.redirectURI = redirectURI
    }
}

public struct MicrosoftOAuthTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let tokenType: String
    public let scope: String?
    public let obtainedAt: Date

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        tokenType: String = "Bearer",
        scope: String? = nil,
        obtainedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
        self.obtainedAt = obtainedAt
    }

    public func expires(within interval: TimeInterval, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= interval
    }
}

public enum MicrosoftOAuthError: Error, LocalizedError, Sendable, Equatable {
    case missingClientID
    case missingCallbackScheme
    case invalidCallback
    case authorizationFailed(code: String, description: String?)
    case stateMismatch
    case missingAuthorizationCode
    case tokenRequestFailed(statusCode: Int, code: String?, description: String?)
    case invalidTokenResponse
    case missingRefreshToken
    case needsReauthentication(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            "This build does not include Microsoft OAuth configuration."
        case .missingCallbackScheme:
            "This build does not include a Microsoft OAuth callback scheme."
        case .invalidCallback:
            "Microsoft sign-in returned an invalid callback."
        case .authorizationFailed(let code, let description):
            description.map { "\(code): \($0)" } ?? code
        case .stateMismatch:
            "Microsoft sign-in state did not match the setup session."
        case .missingAuthorizationCode:
            "Microsoft sign-in did not return an authorization code."
        case .tokenRequestFailed(let statusCode, let code, let description):
            [code, description].compactMap(\.self).joined(separator: ": ").nilIfBlank
                ?? "Microsoft token request failed with HTTP \(statusCode)."
        case .invalidTokenResponse:
            "Microsoft token response was missing required fields."
        case .missingRefreshToken:
            "Microsoft token set does not include a refresh token."
        case .needsReauthentication(let reason):
            reason
        }
    }
}

public struct MicrosoftOAuthHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol MicrosoftOAuthHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> MicrosoftOAuthHTTPResponse
}

public struct URLSessionMicrosoftOAuthHTTPClient: MicrosoftOAuthHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> MicrosoftOAuthHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftOAuthError.invalidTokenResponse
        }
        return MicrosoftOAuthHTTPResponse(statusCode: http.statusCode, data: data)
    }
}

public struct MicrosoftOAuthClient: Sendable {
    public let config: LocalAuthConfig
    public let httpClient: any MicrosoftOAuthHTTPClient
    public let now: @Sendable () -> Date

    public init(
        config: LocalAuthConfig,
        httpClient: any MicrosoftOAuthHTTPClient = URLSessionMicrosoftOAuthHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.httpClient = httpClient
        self.now = now
    }

    public func makeAuthorizationRequest(
        emailAddress: String? = nil,
        state: String = UUID().uuidString,
        codeVerifier: String = Self.generateCodeVerifier()
    ) throws -> MicrosoftOAuthAuthorizationRequest {
        guard let clientID = config.microsoftClientID else {
            throw MicrosoftOAuthError.missingClientID
        }
        guard let callbackScheme = config.microsoftCallbackScheme else {
            throw MicrosoftOAuthError.missingCallbackScheme
        }

        let redirectURI = config.microsoftRedirectURI ?? "\(callbackScheme)://oauth/callback"
        let codeChallenge = Self.codeChallenge(for: codeVerifier)
        var components = URLComponents(url: MailProviderCatalog.microsoftOAuth.authorizationEndpoint, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: MailProviderCatalog.microsoftOAuth.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if let emailAddress = emailAddress?.nilIfBlank {
            queryItems.append(URLQueryItem(name: "login_hint", value: emailAddress))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MicrosoftOAuthError.invalidCallback
        }
        return MicrosoftOAuthAuthorizationRequest(
            authorizationURL: url,
            callbackScheme: callbackScheme,
            state: state,
            codeVerifier: codeVerifier,
            codeChallenge: codeChallenge,
            redirectURI: redirectURI
        )
    }

    public func tokenSet(
        fromCallbackURL callbackURL: URL,
        matching request: MicrosoftOAuthAuthorizationRequest
    ) async throws -> MicrosoftOAuthTokenSet {
        guard callbackURL.scheme == request.callbackScheme,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw MicrosoftOAuthError.invalidCallback
        }
        let queryItems = components.queryItems ?? []
        let returnedState = queryItems.first { $0.name == "state" }?.value
        guard returnedState == request.state else {
            throw MicrosoftOAuthError.stateMismatch
        }
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first { $0.name == "error_description" }?.value
            throw MicrosoftOAuthError.authorizationFailed(code: error, description: description)
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value?.nilIfBlank else {
            throw MicrosoftOAuthError.missingAuthorizationCode
        }
        return try await exchangeAuthorizationCode(code, request: request)
    }

    public func exchangeAuthorizationCode(
        _ code: String,
        request authorizationRequest: MicrosoftOAuthAuthorizationRequest
    ) async throws -> MicrosoftOAuthTokenSet {
        guard let clientID = config.microsoftClientID else {
            throw MicrosoftOAuthError.missingClientID
        }
        let body = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": authorizationRequest.redirectURI,
            "code_verifier": authorizationRequest.codeVerifier,
        ]
        return try await performTokenRequest(body: body)
    }

    public func refresh(_ tokenSet: MicrosoftOAuthTokenSet) async throws -> MicrosoftOAuthTokenSet {
        guard let clientID = config.microsoftClientID else {
            throw MicrosoftOAuthError.missingClientID
        }
        guard let refreshToken = tokenSet.refreshToken?.nilIfBlank else {
            throw MicrosoftOAuthError.missingRefreshToken
        }
        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        return try await performTokenRequest(body: body, fallbackRefreshToken: refreshToken)
    }

    public func storeTokenSet(
        _ tokenSet: MicrosoftOAuthTokenSet,
        accountID: String,
        secretStore: KeychainMailSecretStore = KeychainMailSecretStore()
    ) throws {
        let data = try JSONEncoder().encode(tokenSet)
        let reference = KeychainMailSecretStore.microsoftTokenReference(accountID: accountID)
        guard secretStore.store(data, reference: reference) else {
            throw ManifoldError.email("Failed to store Microsoft OAuth token set in Keychain")
        }
    }

    public func loadTokenSet(
        accountID: String,
        secretStore: KeychainMailSecretStore = KeychainMailSecretStore()
    ) throws -> MicrosoftOAuthTokenSet? {
        let reference = KeychainMailSecretStore.microsoftTokenReference(accountID: accountID)
        guard let data = secretStore.retrieve(reference: reference) else { return nil }
        return try JSONDecoder().decode(MicrosoftOAuthTokenSet.self, from: data)
    }

    @discardableResult
    public func deleteTokenSet(
        accountID: String,
        secretStore: KeychainMailSecretStore = KeychainMailSecretStore()
    ) -> Bool {
        let reference = KeychainMailSecretStore.microsoftTokenReference(accountID: accountID)
        return secretStore.delete(reference: reference)
    }

    public static func generateCodeVerifier(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncoded
    }

    public static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded
    }

    private func performTokenRequest(
        body: [String: String],
        fallbackRefreshToken: String? = nil
    ) async throws -> MicrosoftOAuthTokenSet {
        var request = URLRequest(url: MailProviderCatalog.microsoftOAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.percentEncodedForm(body).data(using: .utf8)

        let response = try await httpClient.data(for: request)
        guard response.statusCode == 200 else {
            let oauthError = Self.parseOAuthError(from: response.data)
            throw MicrosoftOAuthError.tokenRequestFailed(
                statusCode: response.statusCode,
                code: oauthError.code,
                description: oauthError.description
            )
        }
        return try Self.parseTokenSet(
            from: response.data,
            fallbackRefreshToken: fallbackRefreshToken,
            obtainedAt: now()
        )
    }

    static func parseTokenSet(
        from data: Data,
        fallbackRefreshToken: String?,
        obtainedAt: Date
    ) throws -> MicrosoftOAuthTokenSet {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw MicrosoftOAuthError.invalidTokenResponse
        }
        let expiresIn = Self.number(json["expires_in"]) ?? 3600
        let refreshToken = (json["refresh_token"] as? String)?.nilIfBlank ?? fallbackRefreshToken
        let tokenType = (json["token_type"] as? String)?.nilIfBlank ?? "Bearer"
        let scope = (json["scope"] as? String)?.nilIfBlank
        return MicrosoftOAuthTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: obtainedAt.addingTimeInterval(TimeInterval(expiresIn)),
            tokenType: tokenType,
            scope: scope,
            obtainedAt: obtainedAt
        )
    }

    static func parseOAuthError(from data: Data) -> (code: String?, description: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, String(data: data, encoding: .utf8)?.nilIfBlank)
        }
        return (
            json["error"] as? String,
            (json["error_description"] as? String) ?? (json["error_codes"] as? [Any])?.description
        )
    }

    static func percentEncodedForm(_ values: [String: String]) -> String {
        values
            .sorted { $0.key < $1.key }
            .map { "\($0.key.formURLEncoded)=\($0.value.formURLEncoded)" }
            .joined(separator: "&")
    }

    private static func number(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var formURLEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
