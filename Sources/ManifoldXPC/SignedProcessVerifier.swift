// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Security

struct ProcessAttestation: Sendable, Hashable {
    let processID: pid_t
    let identifier: String?
    let teamIdentifier: String?
    /// Result of `SecCodeCheckValidity` against the running process.
    /// False when the in-memory code no longer matches the on-disk
    /// binary — typically because the binary has been replaced under
    /// the running process (e.g. an app launch reinstalled the helper).
    let signatureValid: Bool
    /// Result of `SecStaticCodeCheckValidity` against the binary the
    /// process was launched from. True when the on-disk file is
    /// well-signed even if the running process is a stale instance.
    /// Used by callers to distinguish "stale helper, restart needed"
    /// from "this binary is genuinely untrusted".
    let staticSignatureValid: Bool
    let usedAuditToken: Bool

    /// True when the process is running a stale copy of an otherwise
    /// well-signed helper. This is the single signal Manifold uses to
    /// recommend a "Reconnect agents" action instead of a generic
    /// "signature invalid" rejection.
    var isStaleHelper: Bool {
        !signatureValid && staticSignatureValid
    }
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

        // When the dynamic check fails, also validate the on-disk
        // binary the process was launched from. If that passes, the
        // running process is just stale — relaunch will fix it. If both
        // fail, the binary is genuinely untrusted.
        let staticSignatureValid: Bool
        if signatureValid {
            staticSignatureValid = true
        } else if let executablePath = executablePath(for: processID),
                  let staticURL = URL(fileURLWithPath: executablePath) as URL? {
            staticSignatureValid = staticBinaryIsValid(at: staticURL)
        } else {
            staticSignatureValid = false
        }

        return ProcessAttestation(
            processID: processID,
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            signatureValid: signatureValid,
            staticSignatureValid: staticSignatureValid,
            usedAuditToken: auditTokenData != nil
        )
    }

    private static func staticBinaryIsValid(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess
    }

    private static func executablePath(for processID: pid_t) -> String? {
        let bufferSize = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let result = proc_pidpath(processID, &buffer, UInt32(bufferSize))
        guard result > 0 else { return nil }
        return String(cString: buffer)
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

    static func satisfiesStaticDesignatedRequirement(
        at url: URL,
        identifier: String,
        teamIdentifier: String?
    ) -> Bool {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess,
              let staticCode,
              let requirement = designatedRequirement(identifier: identifier, teamIdentifier: teamIdentifier) else {
            return false
        }

        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement) == errSecSuccess
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
