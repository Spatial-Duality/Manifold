import Foundation

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
