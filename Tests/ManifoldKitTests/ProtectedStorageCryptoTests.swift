// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("ProtectedStorageCrypto")
struct ProtectedStorageCryptoTests {
    @Test("Encrypt and decrypt roundtrip protected payloads")
    func encryptDecryptRoundtrip() throws {
        let plaintext = Data("secret local content".utf8)
        let encrypted = try ProtectedStorageCrypto.encrypt(plaintext)
        let decrypted = try ProtectedStorageCrypto.decrypt(encrypted)

        #expect(encrypted != plaintext)
        #expect(ProtectedStorageCrypto.isEncryptedPayload(encrypted))
        #expect(decrypted == plaintext)
    }

    @Test("Decrypt keeps legacy plaintext payloads readable")
    func decryptKeepsPlaintextPayloadsReadable() throws {
        let plaintext = Data("legacy plaintext".utf8)
        let decrypted = try ProtectedStorageCrypto.decrypt(plaintext)
        #expect(decrypted == plaintext)
    }
}
