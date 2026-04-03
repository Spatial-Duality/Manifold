import SwiftUI
import ManifoldKit

/// Sheet showing side-by-side diff before promoting a file back to source.
/// On macOS 26 this is presented as a sheet, which receives Liquid Glass chrome automatically.
struct PromoteDiffView: View {
    let filePath: String
    let diffLines: [ManifoldKit.DiffLine]
    let onApply: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Promote to source")
                        .font(.headline)
                    Text(filePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Skip") { onSkip() }
                    .buttonStyle(.bordered)
                Button("Apply") { onApply() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            // Diff
            if diffLines.isEmpty {
                VStack {
                    Spacer()
                    Text("No changes to show")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(diffLines) { line in
                            HStack(spacing: 0) {
                                Text(linePrefix(line))
                                    .frame(width: 16, alignment: .center)
                                    .foregroundStyle(lineColor(line).opacity(0.5))
                                Text(line.text)
                                Spacer()
                            }
                            .font(.caption.monospaced())
                            .foregroundStyle(lineColor(line))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .background(lineBackground(line))
                        }
                    }
                    .padding(.vertical, 8)
                    .background(.quinary, in: .rect(cornerRadius: 8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 350)
    }

    private func linePrefix(_ line: ManifoldKit.DiffLine) -> String {
        switch line.type {
        case .context: return " "
        case .addition: return "+"
        case .removal: return "-"
        }
    }

    private func lineColor(_ line: ManifoldKit.DiffLine) -> Color {
        switch line.type {
        case .context: return .secondary
        case .addition: return .green
        case .removal: return .red
        }
    }

    private func lineBackground(_ line: ManifoldKit.DiffLine) -> Color {
        switch line.type {
        case .context: return .clear
        case .addition: return .green.opacity(0.05)
        case .removal: return .red.opacity(0.05)
        }
    }
}
