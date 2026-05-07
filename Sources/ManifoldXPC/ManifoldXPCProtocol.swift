// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

@objc public protocol ManifoldXPCProtocol {
    func callTool(
        connectionID: String,
        requestID: String,
        toolName: String,
        arguments: Data,
        reply: @escaping (Data, Bool) -> Void
    )

    func command(
        requestID: String,
        name: String,
        payload: Data,
        reply: @escaping (Data, NSError?) -> Void
    )

    func connect(
        requestID: String,
        agent: String,
        clientName: String,
        clientVersion: String,
        initializeParams: Data,
        reply: @escaping (String?, NSError?) -> Void
    )

    func disconnect(connectionID: String)
}
