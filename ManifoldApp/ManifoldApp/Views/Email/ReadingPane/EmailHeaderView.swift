import SwiftUI
import ManifoldKit

struct EmailHeaderView: View {
    let message: EmailMessageRecord

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.section) {
            // Avatar circle with sender initial
            ZStack {
                Circle()
                    .fill(avatarColor)
                Text(senderInitial)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Spacing.standard) {
                Text(message.subject)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.standard, verticalSpacing: 4) {
                    GridRow {
                        Text("From")
                            .font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(message.sender)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    if !message.recipients.isEmpty {
                        GridRow {
                            Text("To")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(message.recipients)
                                .font(.callout)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                    if !message.cc.isEmpty {
                        GridRow {
                            Text("Cc")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(message.cc)
                                .font(.callout)
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                    GridRow {
                        Text("Date")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(fullDate)
                            .font(.callout)
                    }
                    if let size = formattedSize {
                        GridRow {
                            Text("Size")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(size)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var senderInitial: String {
        let name = message.sender.trimmingCharacters(in: .whitespaces)
        if let first = name.first, first != "<" {
            return String(first).uppercased()
        }
        return "?"
    }

    private var avatarColor: Color {
        // Deterministic color from sender email
        let hash = abs((message.senderEmail ?? message.sender).hashValue)
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .cyan, .indigo, .mint, .teal]
        return colors[hash % colors.count]
    }

    private var fullDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: message.receivedAt) else { return message.receivedAt }
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        return df.string(from: date)
    }

    private var formattedSize: String? {
        guard message.sizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(message.sizeBytes), countStyle: .file)
    }
}
