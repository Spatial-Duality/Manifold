// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Microsoft OAuth client")
struct MicrosoftOAuthClientTests {
    @Test("PKCE S256 challenge follows RFC 7636")
    func pkceChallenge() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(MicrosoftOAuthClient.codeChallenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Authorization URL uses local public client config without a client secret")
    func authorizationURLUsesPublicClientConfig() throws {
        let client = MicrosoftOAuthClient(
            config: LocalAuthConfig(
                microsoftClientID: "client-id",
                microsoftRedirectURI: "manifold-test://oauth/callback",
                microsoftCallbackScheme: "manifold-test"
            )
        )

        let request = try client.makeAuthorizationRequest(
            emailAddress: "person@example.com",
            state: "state-123",
            codeVerifier: "verifier-123"
        )

        #expect(request.callbackScheme == "manifold-test")
        #expect(request.redirectURI == "manifold-test://oauth/callback")
        let components = try #require(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(query["client_id"] == "client-id")
        #expect(query["response_type"] == "code")
        #expect(query["redirect_uri"] == "manifold-test://oauth/callback")
        #expect(query["scope"]?.contains("offline_access") == true)
        #expect(query["scope"]?.contains("https://outlook.office.com/IMAP.AccessAsUser.All") == true)
        #expect(query["state"] == "state-123")
        #expect(query["code_challenge"] == MicrosoftOAuthClient.codeChallenge(for: "verifier-123"))
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["login_hint"] == "person@example.com")
        #expect(query["client_secret"] == nil)
    }

    @Test("Missing Microsoft client ID fails before sign-in")
    func missingClientIDFails() {
        let client = MicrosoftOAuthClient(config: LocalAuthConfig(microsoftCallbackScheme: "manifold-test"))
        do {
            _ = try client.makeAuthorizationRequest()
            Issue.record("Expected missing client ID failure")
        } catch let error as MicrosoftOAuthError {
            #expect(error == .missingClientID)
        } catch {
            Issue.record("Expected MicrosoftOAuthError, got \(error)")
        }
    }

    @Test("Callback state mismatch is rejected before token exchange")
    func stateMismatchFails() async throws {
        let http = RecordingMicrosoftOAuthHTTPClient(responses: [
            MicrosoftOAuthHTTPResponse(statusCode: 200, data: Data())
        ])
        let client = MicrosoftOAuthClient(
            config: configuredAuth,
            httpClient: http
        )
        let request = try client.makeAuthorizationRequest(state: "expected", codeVerifier: "verifier")
        let callback = try #require(URL(string: "manifold-test://oauth/callback?state=wrong&code=abc"))

        do {
            _ = try await client.tokenSet(fromCallbackURL: callback, matching: request)
            Issue.record("Expected state mismatch failure")
        } catch let error as MicrosoftOAuthError {
            #expect(error == .stateMismatch)
        } catch {
            Issue.record("Expected MicrosoftOAuthError, got \(error)")
        }
        #expect(await http.requestCount() == 0)
    }

    @Test("Authorization code exchange stores token response shape")
    func tokenExchangeSuccess() async throws {
        let body = #"{"access_token":"access-1","refresh_token":"refresh-1","expires_in":3600,"token_type":"Bearer","scope":"offline_access https://outlook.office.com/IMAP.AccessAsUser.All"}"#
        let http = RecordingMicrosoftOAuthHTTPClient(responses: [
            MicrosoftOAuthHTTPResponse(statusCode: 200, data: Data(body.utf8))
        ])
        let now = Date(timeIntervalSince1970: 100)
        let client = MicrosoftOAuthClient(
            config: configuredAuth,
            httpClient: http,
            now: { now }
        )
        let request = try client.makeAuthorizationRequest(state: "state", codeVerifier: "verifier")
        let callback = try #require(URL(string: "manifold-test://oauth/callback?state=state&code=code-1"))

        let tokens = try await client.tokenSet(fromCallbackURL: callback, matching: request)

        #expect(tokens.accessToken == "access-1")
        #expect(tokens.refreshToken == "refresh-1")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: 3700))
        let requests = await http.requests()
        let sent = try #require(requests.first)
        let form = String(data: sent.httpBody ?? Data(), encoding: .utf8)
        #expect(form?.contains("grant_type=authorization_code") == true)
        #expect(form?.contains("client_id=client-id") == true)
        #expect(form?.contains("code=code-1") == true)
        #expect(form?.contains("code_verifier=verifier") == true)
        #expect(form?.contains("client_secret") == false)
    }

    @Test("Refresh preserves previous refresh token if server omits a new one")
    func refreshSuccess() async throws {
        let body = #"{"access_token":"access-2","expires_in":"120","token_type":"Bearer"}"#
        let http = RecordingMicrosoftOAuthHTTPClient(responses: [
            MicrosoftOAuthHTTPResponse(statusCode: 200, data: Data(body.utf8))
        ])
        let now = Date(timeIntervalSince1970: 50)
        let client = MicrosoftOAuthClient(config: configuredAuth, httpClient: http, now: { now })
        let current = MicrosoftOAuthTokenSet(
            accessToken: "old",
            refreshToken: "refresh-1",
            expiresAt: now,
            obtainedAt: now
        )

        let refreshed = try await client.refresh(current)

        #expect(refreshed.accessToken == "access-2")
        #expect(refreshed.refreshToken == "refresh-1")
        #expect(refreshed.expiresAt == Date(timeIntervalSince1970: 170))
        let requests = await http.requests()
        let form = String(data: try #require(requests.first?.httpBody), encoding: .utf8)
        #expect(form?.contains("grant_type=refresh_token") == true)
        #expect(form?.contains("refresh_token=refresh-1") == true)
    }

    @Test("Token errors expose provider code for UI mapping")
    func tokenErrorMapping() async throws {
        let body = #"{"error":"invalid_grant","error_description":"Refresh token expired"}"#
        let http = RecordingMicrosoftOAuthHTTPClient(responses: [
            MicrosoftOAuthHTTPResponse(statusCode: 400, data: Data(body.utf8))
        ])
        let client = MicrosoftOAuthClient(config: configuredAuth, httpClient: http)
        let current = MicrosoftOAuthTokenSet(
            accessToken: "old",
            refreshToken: "refresh-1",
            expiresAt: Date()
        )

        do {
            _ = try await client.refresh(current)
            Issue.record("Expected token request failure")
        } catch let error as MicrosoftOAuthError {
            #expect(error == .tokenRequestFailed(statusCode: 400, code: "invalid_grant", description: "Refresh token expired"))
        }
    }

    private var configuredAuth: LocalAuthConfig {
        LocalAuthConfig(
            microsoftClientID: "client-id",
            microsoftRedirectURI: "manifold-test://oauth/callback",
            microsoftCallbackScheme: "manifold-test"
        )
    }
}

private actor RecordingMicrosoftOAuthHTTPClient: MicrosoftOAuthHTTPClient {
    private var pendingResponses: [MicrosoftOAuthHTTPResponse]
    private var recordedRequests: [URLRequest] = []

    init(responses: [MicrosoftOAuthHTTPResponse]) {
        self.pendingResponses = responses
    }

    func data(for request: URLRequest) async throws -> MicrosoftOAuthHTTPResponse {
        recordedRequests.append(request)
        guard !pendingResponses.isEmpty else {
            throw MicrosoftOAuthError.invalidTokenResponse
        }
        return pendingResponses.removeFirst()
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }

    func requestCount() -> Int {
        recordedRequests.count
    }
}
