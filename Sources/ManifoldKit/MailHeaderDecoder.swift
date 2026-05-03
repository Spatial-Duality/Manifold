// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MailHeaderDecoder {
    private static let encodedWordPattern =
        #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#

    public static func decode(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let nsValue = value as NSString
        guard let regex = try? NSRegularExpression(pattern: encodedWordPattern) else {
            return value
        }
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        guard !matches.isEmpty else { return value }

        var result = ""
        var cursor = 0
        for match in matches {
            let range = match.range
            if range.location > cursor {
                result += nsValue.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            let charset = nsValue.substring(with: match.range(at: 1))
            let encoding = nsValue.substring(with: match.range(at: 2)).uppercased()
            let payload = nsValue.substring(with: match.range(at: 3))
            result += decodeWord(payload: payload, encoding: encoding, charset: charset)
            cursor = range.location + range.length
        }
        if cursor < nsValue.length {
            result += nsValue.substring(from: cursor)
        }
        return result
            .replacingOccurrences(of: "\\?=\\s+=\\?", with: "?==?", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeWord(payload: String, encoding: String, charset: String) -> String {
        let data: Data?
        if encoding == "B" {
            data = Data(base64Encoded: payload)
        } else {
            data = decodeQEncoded(payload)
        }
        guard let data else { return payload }
        return string(from: data, charset: charset) ?? payload
    }

    private static func decodeQEncoded(_ payload: String) -> Data {
        var bytes: [UInt8] = []
        let scalars = Array(payload.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "_" {
                bytes.append(0x20)
                index += 1
            } else if scalar == "=", index + 2 < scalars.count {
                let hex = String(Character(scalars[index + 1])) + String(Character(scalars[index + 2]))
                if let byte = UInt8(hex, radix: 16) {
                    bytes.append(byte)
                    index += 3
                } else {
                    bytes.append(UInt8(ascii: "="))
                    index += 1
                }
            } else if scalar.isASCII {
                bytes.append(UInt8(scalar.value))
                index += 1
            } else {
                bytes.append(contentsOf: String(Character(scalar)).utf8)
                index += 1
            }
        }
        return Data(bytes)
    }

    private static func string(from data: Data, charset: String) -> String? {
        let normalized = charset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let encoding: String.Encoding
        switch normalized {
        case "utf-8", "utf8":
            encoding = .utf8
        case "iso-8859-1", "latin1", "latin-1":
            encoding = .isoLatin1
        case "us-ascii", "ascii":
            encoding = .ascii
        default:
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
