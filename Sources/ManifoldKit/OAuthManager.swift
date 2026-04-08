import Foundation
import AuthenticationServices
import CryptoKit
import os

private let logger = Logger(subsystem: "com.spatialduality.manifold", category: "oauth")

/// Manages OAuth2 authentication flows for Gmail and Microsoft 365.
/// Uses ASWebAuthenticationSession for the browser-based auth flow.
/// Tokens are stored in the macOS Keychain via KeychainHelper.
public actor OAuthManager {

    // MARK: - Provider Configuration

    /// OAuth2 configuration for a provider.
    public struct OAuthConfig: Sendable {
        public let provider: EmailProvider
        public let clientID: String
        public let authURL: String
        public let tokenURL: String
        public let scopes: [String]
        public let redirectScheme: String

        /// Gmail OAuth2 config. Requires a registered Google Cloud client ID.
        public static func gmail(clientID: String) -> OAuthConfig {
            OAuthConfig(
                provider: .gmail,
                clientID: clientID,
                authURL: "https://accounts.google.com/o/oauth2/v2/auth",
                tokenURL: "https://oauth2.googleapis.com/token",
                scopes: ["https://mail.google.com/"],
                redirectScheme: "com.spatialduality.manifold"
            )
        }

        /// Microsoft 365 OAuth2 config. Requires an Azure AD / Entra ID client ID.
        /// Note: The scope MUST use `outlook.office.com` (not `office365.com`).
        /// `office365.com` is for client-credentials flow; delegated user access uses `office.com`.
        public static func microsoft(clientID: String) -> OAuthConfig {
            OAuthConfig(
                provider: .outlook,
                clientID: clientID,
                authURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                scopes: [
                    "https://outlook.office.com/IMAP.AccessAsUser.All",
                    "offline_access",
                ],
                redirectScheme: "com.spatialduality.manifold"
            )
        }
    }

    /// Token pair returned from OAuth2 flow.
    public struct TokenPair: Codable, Sendable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresIn: Int?
        public let tokenType: String?
        public let scope: String?
        public let obtainedAt: Date

        public var isExpired: Bool {
            guard let expiresIn else { return false }
            return Date().timeIntervalSince(obtainedAt) > TimeInterval(expiresIn - 60)
        }
    }

    // MARK: - Stored Configs

    private var configs: [EmailProvider: OAuthConfig] = [:]

    public init() {}

    /// Register an OAuth config for a provider.
    public func register(config: OAuthConfig) {
        configs[config.provider] = config
    }

    /// Check if OAuth is configured for a provider.
    public func isConfigured(for provider: EmailProvider) -> Bool {
        configs[provider] != nil
    }

    // MARK: - Auth Flow

    /// Start the OAuth2 authorization flow with PKCE. Returns a TokenPair on success.
    /// Must be called from MainActor context (presents browser window).
    public func authorize(provider: EmailProvider) async throws -> TokenPair {
        guard let config = configs[provider] else {
            throw ManifoldError.email("OAuth not configured for \(provider.displayName)")
        }

        // PKCE: generate code_verifier and code_challenge
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        let code = try await requestAuthorizationCode(config: config, codeChallenge: codeChallenge)
        let tokens = try await exchangeCodeForTokens(code: code, config: config, codeVerifier: codeVerifier)
        return tokens
    }

    /// Refresh an expired access token using the refresh token.
    public func refresh(provider: EmailProvider, refreshToken: String) async throws -> TokenPair {
        guard let config = configs[provider] else {
            throw ManifoldError.email("OAuth not configured for \(provider.displayName)")
        }

        return try await refreshAccessToken(refreshToken: refreshToken, config: config)
    }

    /// Load stored tokens for an account, refreshing if expired.
    public func validAccessToken(
        accountID: String,
        provider: EmailProvider
    ) async throws -> String {
        guard let stored = loadTokens(accountID: accountID) else {
            throw ManifoldError.email("No OAuth tokens stored for account \(accountID)")
        }

        if !stored.isExpired {
            return stored.accessToken
        }

        guard let refreshToken = stored.refreshToken else {
            throw ManifoldError.email("Access token expired and no refresh token available")
        }

        let refreshed = try await refresh(provider: provider, refreshToken: refreshToken)
        saveTokens(refreshed, accountID: accountID)
        return refreshed.accessToken
    }

    // MARK: - Token Storage (Keychain)

    /// Save OAuth tokens for an account.
    public func saveTokens(_ tokens: TokenPair, accountID: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let key = "oauth.\(accountID)"
        _ = KeychainHelper.store(accountID: key, credential: String(data: data, encoding: .utf8) ?? "")
    }

    /// Load OAuth tokens for an account.
    public func loadTokens(accountID: String) -> TokenPair? {
        let key = "oauth.\(accountID)"
        guard let json = KeychainHelper.retrieve(accountID: key),
              let data = json.data(using: .utf8),
              let tokens = try? JSONDecoder().decode(TokenPair.self, from: data) else { return nil }
        return tokens
    }

    /// Delete stored tokens for an account.
    public func deleteTokens(accountID: String) {
        let key = "oauth.\(accountID)"
        KeychainHelper.delete(accountID: key)
    }

    // MARK: - XOAUTH2 SASL

    /// Build the XOAUTH2 SASL string for IMAP AUTHENTICATE.
    /// Format: base64("user=" + user + "\x01auth=Bearer " + token + "\x01\x01")
    public nonisolated static func xoauth2String(user: String, accessToken: String) -> String {
        let raw = "user=\(user)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return Data(raw.utf8).base64EncodedString()
    }

    // MARK: - Private

    private func requestAuthorizationCode(config: OAuthConfig, codeChallenge: String) async throws -> String {
        let state = UUID().uuidString
        let scopeString = config.scopes.joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let redirectURI = "\(config.redirectScheme)://oauth/callback"
        let encodedRedirect = redirectURI
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI

        var urlString = "\(config.authURL)"
        urlString += "?client_id=\(config.clientID)"
        urlString += "&response_type=code"
        urlString += "&redirect_uri=\(encodedRedirect)"
        urlString += "&scope=\(scopeString)"
        urlString += "&state=\(state)"
        urlString += "&access_type=offline"
        urlString += "&prompt=consent"
        urlString += "&code_challenge=\(codeChallenge)"
        urlString += "&code_challenge_method=S256"

        guard let url = URL(string: urlString) else {
            throw ManifoldError.email("Invalid OAuth authorization URL")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: config.redirectScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: ManifoldError.email("OAuth cancelled: \(error.localizedDescription)"))
                    return
                }
                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: ManifoldError.email("No authorization code in OAuth callback"))
                    return
                }
                let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
                guard returnedState == state else {
                    continuation.resume(throwing: ManifoldError.email("OAuth state mismatch"))
                    return
                }
                continuation.resume(returning: code)
            }
            session.prefersEphemeralWebBrowserSession = false

            // ASWebAuthenticationSession needs to be started on the main thread
            DispatchQueue.main.async {
                session.start()
            }
        }
    }

    private func exchangeCodeForTokens(code: String, config: OAuthConfig, codeVerifier: String) async throws -> TokenPair {
        let redirectURI = "\(config.redirectScheme)://oauth/callback"
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
        ]

        return try await tokenRequest(url: config.tokenURL, body: body)
    }

    private func refreshAccessToken(refreshToken: String, config: OAuthConfig) async throws -> TokenPair {
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ]

        return try await tokenRequest(url: config.tokenURL, body: body)
    }

    private func tokenRequest(url: String, body: [String: String]) async throws -> TokenPair {
        guard let tokenURL = URL(string: url) else {
            throw ManifoldError.email("Invalid token URL")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManifoldError.email("Invalid token response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw ManifoldError.email("Token request failed (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManifoldError.email("Cannot parse token response")
        }

        guard let accessToken = json["access_token"] as? String else {
            throw ManifoldError.email("No access_token in token response")
        }

        return TokenPair(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: json["expires_in"] as? Int,
            tokenType: json["token_type"] as? String,
            scope: json["scope"] as? String,
            obtainedAt: Date()
        )
    }

    // MARK: - PKCE (Proof Key for Code Exchange)

    /// Generate a cryptographically random code_verifier (43-128 characters, URL-safe).
    nonisolated static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    /// Compute the S256 code_challenge from a code_verifier: Base64URL(SHA256(verifier)).
    nonisolated static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded
    }
}

// MARK: - Base64URL Encoding

private extension Data {
    /// Base64URL encoding (RFC 7636): no padding, URL-safe characters.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
