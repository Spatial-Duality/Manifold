// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum XOAUTH2Builder: Sendable {
    public static func rawPayload(user: String, accessToken: String) -> Data {
        let raw = "user=\(user)\u{001}auth=Bearer \(accessToken)\u{001}\u{001}"
        return Data(raw.utf8)
    }

    public static func payload(user: String, accessToken: String) -> String {
        rawPayload(user: user, accessToken: accessToken).base64EncodedString()
    }
}
