// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public protocol MailAccountCredentialValidating: Sendable {
    func validate(
        endpoint: MailEndpoint,
        username: String,
        password: String,
        usernameRule: MailUsernameRule
    ) async throws -> String
}

extension AppPasswordIMAPValidator: MailAccountCredentialValidating {}

public struct MailAccountCreationRequest: Sendable, Equatable {
    public let displayName: String
    public let providerID: MailProviderID
    public let endpoint: MailEndpoint
    public let username: String
    public let credentialKind: MailCredentialKind
    public let credentialData: Data
    public let selectedMailboxIDs: [String]
    public let indexPrivacyMode: MailIndexPrivacyMode

    public var authType: String {
        switch credentialKind {
        case .appPassword: "app_password"
        case .oauthTokenSet: "oauth2"
        case .manualPassword: "password"
        }
    }

    public init(
        displayName: String,
        providerID: MailProviderID,
        endpoint: MailEndpoint,
        username: String,
        credentialKind: MailCredentialKind,
        credentialData: Data,
        selectedMailboxIDs: [String] = [],
        indexPrivacyMode: MailIndexPrivacyMode = .privateTokenIndex
    ) {
        self.displayName = displayName
        self.providerID = providerID
        self.endpoint = endpoint
        self.username = username
        self.credentialKind = credentialKind
        self.credentialData = credentialData
        self.selectedMailboxIDs = selectedMailboxIDs
        self.indexPrivacyMode = indexPrivacyMode
    }
}

public struct MailAccountCreationResult: Sendable {
    public let accountID: String
    public let syncPlan: MailSyncPlan

    public init(accountID: String, syncPlan: MailSyncPlan) {
        self.accountID = accountID
        self.syncPlan = syncPlan
    }
}

public protocol MailAccountCreating: Sendable {
    func createAccount(_ request: MailAccountCreationRequest) async throws -> MailAccountCreationResult
}

public struct EmailStoreMailAccountCreator: MailAccountCreating {
    private let emailStore: EmailStore
    private let secretStore: KeychainMailSecretStore

    public init(
        emailStore: EmailStore,
        secretStore: KeychainMailSecretStore = KeychainMailSecretStore()
    ) {
        self.emailStore = emailStore
        self.secretStore = secretStore
    }

    public func createAccount(_ request: MailAccountCreationRequest) async throws -> MailAccountCreationResult {
        let account = try emailStore.addEmailAccount(
            displayName: request.displayName,
            providerType: request.providerID.emailProvider.rawValue,
            server: request.endpoint.host,
            port: request.endpoint.port,
            username: request.username,
            authType: request.authType,
            indexPrivacyMode: request.indexPrivacyMode
        )
        let reference = account.mailCredentialReference
            ?? EmailStore.credentialReference(for: request.authType, accountID: account.accountID)
        guard secretStore.store(request.credentialData, reference: reference) else {
            try? emailStore.removeEmailAccount(id: account.accountID)
            throw ManifoldError.email("Failed to store mail credential in Keychain")
        }
        let plan = MailSyncPlan(
            accountID: account.accountID,
            priorityMailboxIDs: request.selectedMailboxIDs,
            selectedMailboxIDs: request.selectedMailboxIDs
        )
        return MailAccountCreationResult(accountID: account.accountID, syncPlan: plan)
    }
}

public actor MailAccountSetupService {
    /// Resolves an IMAP endpoint for an unknown domain. Injectable so tests
    /// can stub the network-backed autoconfig/SRV chain.
    public typealias EndpointDiscovery = @Sendable (_ domain: String) async -> MailDiscoveryService.IMAPServer?

    private struct StagedCredential: Sendable {
        let endpoint: MailEndpoint
        let username: String
        let credentialKind: MailCredentialKind
        let credentialData: Data
    }

    private let validator: any MailAccountCredentialValidating
    private let accountCreator: any MailAccountCreating
    private let authConfig: LocalAuthConfig
    private let microsoftOAuthClient: MicrosoftOAuthClient
    private let discovery: EndpointDiscovery

    private var sessions: [UUID: MailAccountSetupSession] = [:]
    private var stagedCredentials: [UUID: StagedCredential] = [:]
    private var oauthRequests: [UUID: MicrosoftOAuthAuthorizationRequest] = [:]

    public init(
        validator: any MailAccountCredentialValidating = AppPasswordIMAPValidator(),
        accountCreator: any MailAccountCreating,
        authConfig: LocalAuthConfig = .load(),
        microsoftOAuthClient: MicrosoftOAuthClient? = nil,
        discovery: @escaping EndpointDiscovery = { await MailDiscoveryService.discover(domain: $0) }
    ) {
        self.validator = validator
        self.accountCreator = accountCreator
        self.authConfig = authConfig
        self.microsoftOAuthClient = microsoftOAuthClient ?? MicrosoftOAuthClient(config: authConfig)
        self.discovery = discovery
    }

    public func session(id: UUID) -> MailAccountSetupSession? {
        sessions[id]
    }

    public func startSetup(emailAddress: String?) -> MailAccountSetupSession {
        let normalizedEmail = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let candidates = normalizedEmail.map(MailProviderCatalog.detectProviders(emailAddress:)) ?? MailProviderID.allCases
        let session = MailAccountSetupSession(
            emailAddress: normalizedEmail,
            selectedProviderID: candidates.count == 1 ? candidates[0] : nil,
            providerCandidates: candidates,
            state: normalizedEmail == nil ? .started : .providerDetected,
            authMethod: candidates.count == 1 ? MailProviderCatalog.profile(for: candidates[0]).defaultAuthMethod : nil,
            progressMessage: normalizedEmail == nil ? nil : "Choose a provider and review how Manifold will connect."
        )
        sessions[session.id] = session
        return session
    }

    public func selectProvider(sessionID: UUID, providerID: MailProviderID) throws -> MailAccountSetupSession {
        var session = try requireSession(sessionID)
        let profile = MailProviderCatalog.profile(for: providerID)
        session.selectedProviderID = providerID
        session.authMethod = profile.defaultAuthMethod
        session.state = .providerDetected
        session.failureReason = nil
        session.progressMessage = "Review the trust details before entering credentials."
        sessions[sessionID] = session
        stagedCredentials[sessionID] = nil
        oauthRequests[sessionID] = nil
        return session
    }

    public func acceptTrustPanel(sessionID: UUID) throws -> MailAccountSetupSession {
        var session = try requireSession(sessionID)
        let profile = try selectedProfile(for: session)
        session.state = waitingState(for: profile.defaultAuthMethod)
        session.authMethod = profile.defaultAuthMethod
        session.failureReason = nil
        session.progressMessage = progressMessage(for: profile.defaultAuthMethod)
        sessions[sessionID] = session
        return session
    }

    @discardableResult
    public func submitAppPassword(sessionID: UUID, password: String) async throws -> MailAccountSetupSession {
        var session = try requireSession(sessionID)
        let profile = try selectedProfile(for: session)
        guard let endpoint = profile.imapEndpoint else {
            throw ManifoldError.email("Provider does not have a fixed IMAP endpoint")
        }
        guard let email = session.emailAddress?.nilIfBlank else {
            session.state = .failed
            session.failureReason = .invalidEmail
            sessions[sessionID] = session
            return session
        }
        return try await validatePasswordCredential(
            session: session,
            endpoint: endpoint,
            username: email,
            password: password,
            usernameRule: profile.usernameRule,
            credentialKind: .appPassword
        )
    }

    /// Validate a password for an unknown-domain account by discovering the
    /// IMAP endpoint first (autoconfig chain, then DNS SRV), so custom-domain
    /// users enter only their address and password. When discovery finds
    /// nothing, the session returns to `.waitingForCredential` and the UI
    /// falls back to its manual server fields.
    @discardableResult
    public func submitDiscoveredCredential(
        sessionID: UUID,
        password: String
    ) async throws -> MailAccountSetupSession {
        var session = try requireSession(sessionID)
        guard let email = session.emailAddress?.nilIfBlank,
              let domain = email.components(separatedBy: "@").last?.nilIfBlank?.lowercased() else {
            session.state = .failed
            session.failureReason = .invalidEmail
            sessions[sessionID] = session
            return session
        }

        session.state = .validatingCredential
        session.failureReason = nil
        session.progressMessage = "Looking up mail server settings for \(domain)."
        sessions[sessionID] = session

        guard let discovered = await discovery(domain) else {
            session.state = .waitingForCredential
            session.progressMessage = "No published server settings for \(domain). Enter the IMAP server manually."
            sessions[sessionID] = session
            return session
        }

        let endpoint = MailEndpoint(host: discovered.host, port: Int(discovered.port), security: .tlsOnConnect)
        let usernameRule: MailUsernameRule =
            discovered.usernameTemplate == "%EMAILLOCALPART%" ? .localPartThenFullEmailFallback : .fullEmail
        return try await validatePasswordCredential(
            session: session,
            endpoint: endpoint,
            username: email,
            password: password,
            usernameRule: usernameRule,
            credentialKind: .manualPassword
        )
    }

    @discardableResult
    public func submitManualCredential(
        sessionID: UUID,
        endpoint: MailEndpoint,
        username: String,
        password: String
    ) async throws -> MailAccountSetupSession {
        var session = try requireSession(sessionID)
        guard endpoint.security != .insecureDisallowed else {
            session.state = .failed
            session.failureReason = .tlsFailed
            session.progressMessage = "Plain insecure IMAP is disabled."
            sessions[sessionID] = session
            return session
        }
        return try await validatePasswordCredential(
            session: session,
            endpoint: endpoint,
            username: username,
            password: password,
            usernameRule: .userEntered,
            credentialKind: .manualPassword
        )
    }

    public func startOAuth(sessionID: UUID) throws -> MicrosoftOAuthAuthorizationRequest {
        var session = try requireSession(sessionID)
        let profile = try selectedProfile(for: session)
        guard profile.id == .microsoft else {
            throw ManifoldError.email("OAuth setup is only enabled for Microsoft in v1")
        }
        guard authConfig.isMicrosoftOAuthConfigured else {
            session.state = .failed
            session.failureReason = .missingOAuthConfig
            session.progressMessage = "This build does not include Microsoft OAuth configuration."
            sessions[sessionID] = session
            throw MicrosoftOAuthError.missingClientID
        }
        let request = try microsoftOAuthClient.makeAuthorizationRequest(emailAddress: session.emailAddress)
        session.state = .waitingForOAuth
        session.authMethod = profile.defaultAuthMethod
        session.failureReason = nil
        session.progressMessage = "Complete Microsoft sign-in in the browser."
        sessions[sessionID] = session
        oauthRequests[sessionID] = request
        return request
    }

    @discardableResult
    public func completeOAuth(sessionID: UUID, callbackURL: URL) async throws -> MailAccountSetupSession {
        var session = try requireSession(sessionID)
        guard let request = oauthRequests[sessionID] else {
            throw ManifoldError.email("No OAuth request is active for this setup session")
        }
        let profile = try selectedProfile(for: session)
        guard let endpoint = profile.imapEndpoint else {
            throw ManifoldError.email("Microsoft profile is missing its IMAP endpoint")
        }
        session.state = .validatingCredential
        session.failureReason = nil
        session.progressMessage = "Exchanging Microsoft authorization code."
        sessions[sessionID] = session

        do {
            let tokenSet = try await microsoftOAuthClient.tokenSet(fromCallbackURL: callbackURL, matching: request)
            let data = try JSONEncoder().encode(tokenSet)
            stagedCredentials[sessionID] = StagedCredential(
                endpoint: endpoint,
                username: session.emailAddress ?? "",
                credentialKind: .oauthTokenSet,
                credentialData: data
            )
            session.state = .choosingMailboxes
            session.progressMessage = "Microsoft sign-in succeeded. Choose what Manifold should sync."
            sessions[sessionID] = session
            return session
        } catch {
            session.state = .failed
            session.failureReason = mapOAuthFailure(error)
            session.progressMessage = MailLogRedactor().redact(error.localizedDescription)
            sessions[sessionID] = session
            throw error
        }
    }

    public func createAccount(
        sessionID: UUID,
        selectedMailboxIDs: [String] = []
    ) async throws -> MailAccountCreationResult {
        var session = try requireSession(sessionID)
        let profile = try selectedProfile(for: session)
        guard var staged = stagedCredentials[sessionID] else {
            throw ManifoldError.email("Mail setup has no validated credential to store")
        }
        if staged.credentialKind == .oauthTokenSet, staged.username.isEmpty, let email = session.emailAddress {
            staged = StagedCredential(
                endpoint: staged.endpoint,
                username: email,
                credentialKind: staged.credentialKind,
                credentialData: staged.credentialData
            )
        }
        session.state = .creatingAccount
        session.progressMessage = "Creating local mail account."
        sessions[sessionID] = session

        let request = MailAccountCreationRequest(
            displayName: profile.displayName,
            providerID: profile.id,
            endpoint: staged.endpoint,
            username: staged.username,
            credentialKind: staged.credentialKind,
            credentialData: staged.credentialData,
            selectedMailboxIDs: selectedMailboxIDs
        )
        let result = try await accountCreator.createAccount(request)
        session.state = .enrolledForSync
        session.progressMessage = "Account enrolled for local sync."
        session.failureReason = nil
        sessions[sessionID] = session
        stagedCredentials[sessionID] = nil
        oauthRequests[sessionID] = nil
        return result
    }

    private func validatePasswordCredential(
        session: MailAccountSetupSession,
        endpoint: MailEndpoint,
        username: String,
        password: String,
        usernameRule: MailUsernameRule,
        credentialKind: MailCredentialKind
    ) async throws -> MailAccountSetupSession {
        var session = session
        session.state = .validatingCredential
        session.failureReason = nil
        session.progressMessage = "Validating credentials with the mail provider."
        sessions[session.id] = session

        do {
            let validatedUsername = try await validator.validate(
                endpoint: endpoint,
                username: username,
                password: password,
                usernameRule: usernameRule
            )
            session.state = .choosingMailboxes
            session.progressMessage = "Credential validated. Choose what Manifold should sync."
            stagedCredentials[session.id] = StagedCredential(
                endpoint: endpoint,
                username: validatedUsername,
                credentialKind: credentialKind,
                credentialData: Data(password.utf8)
            )
            sessions[session.id] = session
            return session
        } catch {
            session.state = .failed
            session.failureReason = .authenticationFailed
            session.progressMessage = MailLogRedactor().redact(error.localizedDescription)
            stagedCredentials[session.id] = nil
            sessions[session.id] = session
            return session
        }
    }

    private func requireSession(_ id: UUID) throws -> MailAccountSetupSession {
        guard let session = sessions[id] else {
            throw ManifoldError.email("Mail setup session not found")
        }
        return session
    }

    private func selectedProfile(for session: MailAccountSetupSession) throws -> MailProviderProfile {
        guard let providerID = session.selectedProviderID else {
            throw ManifoldError.email("No mail provider selected")
        }
        return MailProviderCatalog.profile(for: providerID)
    }

    private func waitingState(for authMethod: MailAuthMethod) -> MailAccountSetupState {
        switch authMethod {
        case .oauthIMAPXOAUTH2: .waitingForOAuth
        case .appPasswordIMAP, .manualPasswordIMAP: .waitingForCredential
        }
    }

    private func progressMessage(for authMethod: MailAuthMethod) -> String {
        switch authMethod {
        case .oauthIMAPXOAUTH2:
            "Manifold will open Microsoft sign-in and store the token in Keychain after validation."
        case .appPasswordIMAP:
            "Create an app password with your provider and paste it here."
        case .manualPasswordIMAP:
            "Enter your IMAP server and password or app password."
        }
    }

    private func mapOAuthFailure(_ error: Error) -> MailSetupFailureReason {
        if let microsoft = error as? MicrosoftOAuthError {
            switch microsoft {
            case .missingClientID, .missingCallbackScheme:
                return .missingOAuthConfig
            case .authorizationFailed(let code, _):
                if code == "admin_consent_required" || code == "AADSTS65001" {
                    return .adminConsentRequired
                }
                if code == "invalid_client" {
                    return .missingOAuthConfig
                }
                return .authenticationFailed
            case .tokenRequestFailed(_, let code, _):
                if code == "admin_consent_required" || code == "AADSTS65001" {
                    return .adminConsentRequired
                }
                if code == "invalid_client" {
                    return .missingOAuthConfig
                }
                return .authenticationFailed
            case .stateMismatch, .invalidCallback, .missingAuthorizationCode, .invalidTokenResponse:
                return .unexpectedResponse
            case .missingRefreshToken, .needsReauthentication:
                return .authenticationFailed
            }
        }
        return .authenticationFailed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
