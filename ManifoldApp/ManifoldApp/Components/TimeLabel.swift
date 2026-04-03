import SwiftUI

struct TimeLabel: View {
    let iso8601: String

    var body: some View {
        Text(formatted)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
    }

    private var formatted: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else {
            return iso8601.suffix(8).description
        }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        let display = DateFormatter()
        display.dateStyle = .short
        display.timeStyle = .short
        return display.string(from: date)
    }
}
