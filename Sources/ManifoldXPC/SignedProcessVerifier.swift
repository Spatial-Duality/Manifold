// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Security

struct ProcessAttestation: Sendable, Hashable {
    let processID: pid_t
    let identifier: String?
    let teamIdentifier: String?
    let signatureValid: Bool
    let usedAuditToken: Bool
}

enum SignedProcessVerifier {
    static func currentProcessAttestation() -> ProcessAttestation? {
        attestation(processID: getpid())
    }

    static func attestation(for connection: NSXPCConnection?) -> ProcessAttestation? {
        guard let connection else { return nil }
        return attestation(
            processID: connection.processIdentifier,
            auditTokenData: auditTokenData(from: connection)
        )
    }

    static func attestation(processID: pid_t, auditTokenData: Data? = nil) -> ProcessAttestation? {
        guard processID > 0, let code = guestCode(processID: processID, auditTokenData: auditTokenData) else {
            return nil
        }

        guard let staticCode = staticCode(for: code) else {
            return nil
        }

        var infoRef: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &infoRef
        )
        guard infoStatus == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            return nil
        }

        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String
        let signatureValid = SecCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess
        return ProcessAttestation(
            processID: processID,
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            signatureValid: signatureValid,
            usedAuditToken: auditTokenData != nil
        )
    }

    static func satisfiesDesignatedRequirement(
        processID: pid_t,
        auditTokenData: Data? = nil,
        identifier: String,
        teamIdentifier: String?
    ) -> Bool {
        guard processID > 0,
              let code = guestCode(processID: processID, auditTokenData: auditTokenData),
              let requirement = designatedRequirement(identifier: identifier, teamIdentifier: teamIdentifier) else {
            return false
        }

        return SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess
    }

    private static func guestCode(processID: pid_t, auditTokenData: Data?) -> SecCode? {
        var attributes: [CFString: Any] = [
            kSecGuestAttributePid: NSNumber(value: processID),
        ]
        if let auditTokenData {
            attributes[kSecGuestAttributeAudit] = auditTokenData as CFData
        }

        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &code)
        guard status == errSecSuccess else { return nil }
        return code
    }

    private static func designatedRequirement(identifier: String, teamIdentifier: String?) -> SecRequirement? {
        var requirement: SecRequirement?
        let requirementString: String
        if let teamIdentifier, !teamIdentifier.isEmpty {
            requirementString = "identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        } else {
            requirementString = "identifier \"\(identifier)\""
        }

        let status = SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement)
        guard status == errSecSuccess else { return nil }
        return requirement
    }

    private static func staticCode(for code: SecCode) -> SecStaticCode? {
        var staticCode: SecStaticCode?
        let status = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard status == errSecSuccess else { return nil }
        return staticCode
    }

    private static func auditTokenData(from connection: NSXPCConnection) -> Data? {
        guard let rawValue = connection.value(forKey: "auditToken") else { return nil }
        if let data = rawValue as? Data {
            return data
        }
        if let value = rawValue as? NSValue {
            var bytes = [UInt8](repeating: 0, count: 32)
            bytes.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                value.getValue(baseAddress)
            }
            return Data(bytes)
        }
        return nil
    }
}
