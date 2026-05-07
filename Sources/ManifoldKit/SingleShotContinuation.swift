// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Thread-safe guard for callback APIs that may race success, failure,
/// timeout, and invalidation paths. The wrapped checked continuation is
/// resumed at most once; later callbacks are ignored.
public final class SingleShotThrowingContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    public init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    public func resume(returning value: sending Value) -> Bool {
        guard let continuation = take() else { return false }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    public func resume(throwing error: Error) -> Bool {
        guard let continuation = take() else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let current = continuation
        continuation = nil
        return current
    }
}
