import Foundation

// MARK: - Shared ISO8601 Formatter

extension ISO8601DateFormatter {
    /// Thread-safe shared formatter. Read-only after initialization.
    /// Apple docs warn DateFormatter creation is expensive — cache and reuse.
    public nonisolated(unsafe) static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - String Helpers

extension String {
    /// Returns nil if the string is empty, otherwise returns self.
    /// Pro Swift: replace repeated `.flatMap { $0.isEmpty ? nil : $0 }` pattern.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Optional where Wrapped == String {
    /// Unwraps the optional and returns nil if the string is empty.
    var nilIfEmpty: String? {
        flatMap { $0.isEmpty ? nil : $0 }
    }
}
