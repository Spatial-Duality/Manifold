import SwiftUI
import ManifoldKit

/// Sheet showing side-by-side diff before promoting a file back to source.
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
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Skip") { onSkip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lineColor(line))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .background(lineBackground(line))
                        }
                    }
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
