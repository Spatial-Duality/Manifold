import SwiftUI
import ManifoldKit

struct DiffView: View {
    let lines: [DiffLine]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    DiffLineRow(line: line)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .font(.caption.monospaced())
                .foregroundStyle(color)
                .frame(width: 14, alignment: .leading)
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(background)
    }

    private var prefix: String {
        switch line.type {
        case .addition: return "+"
        case .removal: return "-"
        case .context: return " "
        }
    }

    private var color: Color {
        switch line.type {
        case .addition: return .green
        case .removal: return .red
        case .context: return .secondary
        }
    }

    private var background: Color {
        switch line.type {
        case .addition: return .green.opacity(0.08)
        case .removal: return .red.opacity(0.08)
        case .context: return .clear
        }
    }
}
