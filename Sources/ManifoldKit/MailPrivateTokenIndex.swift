// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

public enum MailPrivateTokenField: Int, Sendable, CaseIterable {
    case subject = 1
    case sender = 2
    case recipients = 4
    case body = 8
    case attachment = 16
}

public enum MailPrivateTokenIndex: Sendable {
    private static let maxTokenLength = 128
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let allowedTokenScalars: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "@._-")
        return set
    }()

    public static func normalizedTokens(_ text: String) -> [String] {
        var seen = Set<String>()
        return normalizedTokenSequence(text).filter { seen.insert($0).inserted }
    }

    static func normalizedTokenSequence(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .lowercased()

        var result: [String] = []
        var current = String()

        func flushCurrent() {
            guard !current.isEmpty else { return }
            let token = String(current.prefix(maxTokenLength))
                .trimmingCharacters(in: CharacterSet(charactersIn: "@._-"))
            current.removeAll(keepingCapacity: true)
            guard token.count >= 2 else { return }
            appendToken(token)

            for part in token.split(whereSeparator: { "@._-".contains($0) }).map(String.init) {
                appendToken(part)
            }
        }

        func appendToken(_ token: String) {
            guard token.count >= 2, token.count <= maxTokenLength else { return }
            result.append(token)
        }

        for scalar in folded.unicodeScalars {
            if allowedTokenScalars.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flushCurrent()
            }
        }
        flushCurrent()
        return result
    }

    static func termHMAC(accountID: String, normalizedToken: String) throws -> String {
        let key = try MailArchiveStore.accountDerivedKey(accountID: accountID, purpose: "mail-private-index")
        let payload = Data("v1:\(normalizedToken)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: payload, using: key)).mailPrivateIndexHexString
    }
}

private extension Data {
    var mailPrivateIndexHexString: String {
        let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
        var chars = [UInt8](repeating: 0, count: count * 2)
        for (index, byte) in enumerated() {
            chars[index * 2] = hexDigits[Int(byte >> 4)]
            chars[index * 2 + 1] = hexDigits[Int(byte & 0x0F)]
        }
        return String(bytes: chars, encoding: .ascii) ?? ""
    }
}
