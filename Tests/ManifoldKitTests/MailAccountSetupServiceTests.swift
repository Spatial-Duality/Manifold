// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Mail account setup service")
struct MailAccountSetupServiceTests {
    @Test("Gmail app-password setup validates before account creation")
    func gmailSetupValidatesBeforeCreate() async throws {
        let creator = RecordingMailAccountCreator()
        let service = MailAccountSetupService(
            validator: StubCredentialValidator(validatedUsername: "person@gmail.com"),
            accountCreator: creator,
            authConfig: LocalAuthConfig()
        )

        let started = await service.startSetup(emailAddress: "person@gmail.com")
        #expect(started.providerCandidates == [.gmail])
        #expect(started.state == .providerDetected)

        let trusted = try await service.acceptTrustPanel(sessionID: started.id)
        #expect(trusted.state == .waitingForCredential)

        let validated = try await service.submitAppPassword(sessionID: started.id, password: "app-password")
        #expect(validated.state == .choosingMailboxes)
        #expect(await creator.requestCount() == 0)

        let result = try await service.createAccount(sessionID: started.id, selectedMailboxIDs: ["INBOX"])
        #expect(result.accountID == "created-account")
        let request = try #require(await creator.requests().first)
        #expect(request.providerID == .gmail)
        #expect(request.endpoint == MailEndpoint(host: "imap.gmail.com", port: 993))
        #expect(request.username == "person@gmail.com")
        #expect(request.credentialKind == .appPassword)
        #expect(String(data: request.credentialData, encoding: .utf8) == "app-password")
        #expect(request.selectedMailboxIDs == ["INBOX"])
    }

    @Test("Validation failure is recoverable and stores nothing")
    func validationFailureIsRecoverable() async throws {
        let creator = RecordingMailAccountCreator()
        let service = MailAccountSetupService(
            validator: StubCredentialValidator(validatedUsername: "person@gmail.com", failuresBeforeSuccess: 1),
            accountCreator: creator
        )
        let session = await service.startSetup(emailAddress: "person@gmail.com")
        _ = try await service.acceptTrustPanel(sessionID: session.id)

        let failed = try await service.submitAppPassword(sessionID: session.id, password: "bad")
        #expect(failed.state == .failed)
        #expect(failed.failureReason == .authenticationFailed)
        #expect(await creator.requestCount() == 0)

        let recovered = try await service.submitAppPassword(sessionID: session.id, password: "good")
        #expect(recovered.state == .choosingMailboxes)
        _ = try await service.createAccount(sessionID: session.id)
        let request = try #require(await creator.requests().first)
        #expect(String(data: request.credentialData, encoding: .utf8) == "good")
    }

    @Test("Microsoft OAuth setup fails closed when local config is missing")
    func microsoftMissingConfigFailsClosed() async throws {
        let service = MailAccountSetupService(
            validator: StubCredentialValidator(validatedUsername: "person@outlook.com"),
            accountCreator: RecordingMailAccountCreator(),
            authConfig: LocalAuthConfig()
        )
        let session = await service.startSetup(emailAddress: "person@outlook.com")
        _ = try await service.acceptTrustPanel(sessionID: session.id)

        do {
            _ = try await service.startOAuth(sessionID: session.id)
            Issue.record("Expected missing Microsoft OAuth config")
        } catch let error as MicrosoftOAuthError {
            #expect(error == .missingClientID)
        } catch {
            Issue.record("Expected MicrosoftOAuthError, got \(error)")
        }
        let failed = try #require(await service.session(id: session.id))
        #expect(failed.state == .failed)
        #expect(failed.failureReason == .missingOAuthConfig)
    }

    @Test("Microsoft OAuth setup creates authorization request when configured")
    func microsoftConfiguredStartsOAuth() async throws {
        let service = MailAccountSetupService(
            validator: StubCredentialValidator(validatedUsername: "person@outlook.com"),
            accountCreator: RecordingMailAccountCreator(),
            authConfig: LocalAuthConfig(
                microsoftClientID: "client-id",
                microsoftRedirectURI: "manifold-test://oauth/callback",
                microsoftCallbackScheme: "manifold-test"
            )
        )
        let session = await service.startSetup(emailAddress: "person@outlook.com")
        _ = try await service.acceptTrustPanel(sessionID: session.id)

        let request = try await service.startOAuth(sessionID: session.id)
        #expect(request.callbackScheme == "manifold-test")
        let updated = try #require(await service.session(id: session.id))
        #expect(updated.state == .waitingForOAuth)
        #expect(updated.failureReason == nil)
    }
}

private actor StubCredentialValidator: MailAccountCredentialValidating {
    private let validatedUsername: String
    private var remainingFailures: Int

    init(validatedUsername: String, failuresBeforeSuccess: Int = 0) {
        self.validatedUsername = validatedUsername
        self.remainingFailures = failuresBeforeSuccess
    }

    func validate(
        endpoint: MailEndpoint,
        username: String,
        password: String,
        usernameRule: MailUsernameRule
    ) async throws -> String {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw IMAPError.authenticationFailed("bad credential for \(username)")
        }
        return validatedUsername
    }
}

private actor RecordingMailAccountCreator: MailAccountCreating {
    private var recordedRequests: [MailAccountCreationRequest] = []

    func createAccount(_ request: MailAccountCreationRequest) async throws -> MailAccountCreationResult {
        recordedRequests.append(request)
        return MailAccountCreationResult(
            accountID: "created-account",
            syncPlan: MailSyncPlan(
                accountID: "created-account",
                priorityMailboxIDs: request.selectedMailboxIDs,
                selectedMailboxIDs: request.selectedMailboxIDs
            )
        )
    }

    func requests() -> [MailAccountCreationRequest] {
        recordedRequests
    }

    func requestCount() -> Int {
        recordedRequests.count
    }
}
