import SwiftUI
import ManifoldKit

struct DiffView: View {
    let lines: [DiffLine]
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Copy button
            HStack {
                Spacer()
                Button {
                    let unified = lines.map { line in
                        switch line.type {
                        case .addition: "+\(line.text)"
                        case .removal: "-\(line.text)"
                        case .context: " \(line.text)"
                        }
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(unified, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy Diff", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Typ.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, Spacing.standard)
                .padding(.vertical, Spacing.tight)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        DiffLineRow(line: line, lineNumber: index + 1)
                    }
                }
                .padding(.horizontal, Spacing.standard)
                .padding(.vertical, Spacing.tight)
            }
        }
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let lineNumber: Int

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text("\(lineNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.quaternary)
                .frame(width: 24, alignment: .trailing)
                .padding(.trailing, Spacing.standard)

            // Prefix (+/-/space)
            Text(prefix)
                .font(.caption.monospaced())
                .foregroundStyle(color)
                .frame(width: 14, alignment: .leading)

            // Line content
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.vertical, Spacing.tight)
        .padding(.horizontal, Spacing.tight)
        .background(background)
    }

    private var prefix: String {
        switch line.type {
        case .addition: "+"
        case .removal: "-"
        case .context: " "
        }
    }

    private var color: Color {
        switch line.type {
        case .addition: .green
        case .removal: .red
        case .context: .secondary
        }
    }

    private var background: Color {
        switch line.type {
        case .addition: .green.opacity(0.08)
        case .removal: .red.opacity(0.08)
        case .context: .clear
        }
    }
}
