// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
import Security
@testable import ManifoldKit

/// R5 — pending credential handoff.
///
/// The contract: app writes to a `pending-{uuid}` Keychain slot, sends
/// only the UUID over XPC, agent reads + rotates. These tests pin the
/// Keychain account naming convention and query shape. They do NOT
/// exercise the live login keychain because the test bundle may not
/// have a usable interactive Keychain session.
@Suite("Keychain pending credential handoff")
struct KeychainPendingCredentialTests {

    @Test("Pending app-password reference uses the pending-prefix and credential service")
    func pendingAppPasswordReferenceShape() {
        let pendingID = "test-uuid-1234"
        let ref = KeychainMailSecretStore.pendingReference(
            pendingID: pendingID,
            kind: .appPassword
        )
        #expect(ref.keychainService == KeychainMailSecretStore.credentialService)
        #expect(ref.keychainAccount == "mail-account:pending-\(pendingID):app-password")
        #expect(ref.keychainAccount.hasPrefix(KeychainMailSecretStore.pendingAccountPrefix))
        #expect(ref.kind == .appPassword)
    }

    @Test("Pending manual-password reference uses credential service")
    func pendingManualPasswordReferenceShape() {
        let ref = KeychainMailSecretStore.pendingReference(
            pendingID: "abc",
            kind: .manualPassword
        )
        #expect(ref.keychainService == KeychainMailSecretStore.credentialService)
        #expect(ref.keychainAccount == "mail-account:pending-abc:manual-password")
        #expect(ref.kind == .manualPassword)
    }

    @Test("Pending OAuth token-set reference uses oauth service")
    func pendingOAuthReferenceShape() {
        let ref = KeychainMailSecretStore.pendingReference(
            pendingID: "abc",
            kind: .oauthTokenSet
        )
        #expect(ref.keychainService == KeychainMailSecretStore.oauthService)
        #expect(ref.keychainAccount == "mail-account:pending-abc:microsoft-token-set")
        #expect(ref.kind == .oauthTokenSet)
    }

    @Test("Pending account prefix is distinct from canonical mail-account prefix")
    func pendingPrefixDoesNotCollideWithCanonicalAccountIDs() {
        // The pending prefix must not be a substring that collides with
        // a real account ID. Canonical accounts use "mail-account:{uuid}:..."
        // while pending uses "mail-account:pending-{uuid}:...". The
        // sweep filters by prefix; collision would delete user data.
        let canonical = "mail-account:de305d54-75b4-431b-adb2-eb6b9e546014:app-password"
        let pending = "mail-account:pending-de305d54:app-password"
        #expect(!canonical.hasPrefix(KeychainMailSecretStore.pendingAccountPrefix))
        #expect(pending.hasPrefix(KeychainMailSecretStore.pendingAccountPrefix))
    }

    @Test("Different pendingIDs produce distinct references")
    func pendingReferencesAreUniqueByID() {
        let a = KeychainMailSecretStore.pendingReference(pendingID: "alpha", kind: .appPassword)
        let b = KeychainMailSecretStore.pendingReference(pendingID: "beta", kind: .appPassword)
        #expect(a.keychainAccount != b.keychainAccount)
    }

    @Test("Canonical credential store query prefers the data protection keychain")
    func canonicalStoreQueryUsesDataProtectionKeychain() {
        let secret = Data("canonical-secret".utf8)
        let ref = KeychainMailSecretStore.appPasswordReference(accountID: "account-1")

        let query = KeychainMailSecretStore.dataProtectionStoreQuery(secret, reference: ref)

        #expect(query[kSecAttrService as String] as? String == KeychainMailSecretStore.credentialService)
        #expect(query[kSecAttrAccount as String] as? String == "mail-account:account-1:app-password")
        #expect(query[kSecValueData as String] as? Data == secret)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test("Pending handoff query uses the login keychain so the LaunchAgent can read it")
    func pendingHandoffQueryUsesLoginKeychain() {
        let secret = Data("pending-secret".utf8)
        let ref = KeychainMailSecretStore.pendingReference(pendingID: "handoff-1", kind: .appPassword)

        let query = KeychainMailSecretStore.loginStoreQuery(secret, reference: ref)

        #expect(query[kSecAttrService as String] as? String == KeychainMailSecretStore.credentialService)
        #expect(query[kSecAttrAccount as String] as? String == "mail-account:pending-handoff-1:app-password")
        #expect(query[kSecValueData as String] as? Data == secret)
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
        #expect(query[kSecAttrAccess as String] == nil)
    }

    @Test("Sweep accepts a custom TTL and `now` for testability")
    func sweepIsParameterizable() {
        // The signature must allow tests to drive the cutoff without
        // sleeping. If this compiles and runs, the API supports it.
        let store = KeychainMailSecretStore()
        store.sweepStalePendingCredentials(ttl: 1, now: Date())
        // No assertion: the call must not crash. The actual sweep
        // requires Keychain access not available in the test sandbox.
    }
}
