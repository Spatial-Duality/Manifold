import SwiftUI
import ManifoldKit

struct EmailMessageRow: View {
    let message: EmailMessageRecord
    let isSelected: Bool
    let isShared: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.standard) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(senderName)
                        .font(.callout.weight(.regular))
                        .lineLimit(1)
                    Spacer()
                    if message.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if message.attachmentCount > 0 {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                // Deleted-on-server badge
                if message.isDeletedOnServer {
                    Text("Server deleted")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .accessibilityLabel("Deleted from server")
                }

                Text(message.subject)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let preview = message.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(message.isDeletedOnServer ? 0.7 : 1.0)
    }

    private var senderName: String {
        let s = message.sender
        if let angle = s.firstIndex(of: "<") {
            let name = String(s[..<angle]).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? s : name
        }
        return s
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, y"
        return f
    }()

    private var formattedDate: String {
        let date = Self.isoFormatter.date(from: message.receivedAt)
            ?? Self.isoFallbackFormatter.date(from: message.receivedAt)
        guard let d = date else { return message.receivedAt }

        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return Self.timeFormatter.string(from: d)
        } else if cal.isDateInYesterday(d) {
            return "Yesterday"
        } else if cal.isDate(d, equalTo: .now, toGranularity: .year) {
            return Self.monthDayFormatter.string(from: d)
        } else {
            return Self.fullDateFormatter.string(from: d)
        }
    }
}
