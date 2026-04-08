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
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if message.attachmentCount > 0 {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                // Deleted-on-server badge
                if message.isDeletedOnServer {
                    Text("Server deleted")
                        .font(.caption2)
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

    private var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: message.receivedAt) ?? {
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            return iso2.date(from: message.receivedAt)
        }()

        guard let d = date else { return message.receivedAt }

        let display = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            display.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(d) {
            return "Yesterday"
        } else if cal.isDate(d, equalTo: Date(), toGranularity: .year) {
            display.dateFormat = "MMM d"
        } else {
            display.dateFormat = "MMM d, yyyy"
        }
        return display.string(from: d)
    }
}
