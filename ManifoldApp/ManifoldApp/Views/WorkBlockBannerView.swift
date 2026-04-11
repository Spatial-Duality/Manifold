import SwiftUI
import ManifoldKit

/// Global persistent banner visible on ALL tabs when a Tracked Work Block is active.
/// Shows agent color, duration, modified/new file counts, and action buttons.
struct WorkBlockBannerView: View {
    let block: WorkBlockRecord
    let onFinish: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    @State private var showStopConfirmation = false

    private var agentColor: Color {
        block.agent == .codex ? .purple : .blue
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private func elapsedText(at now: Date) -> String {
        guard let start = Self.isoFormatter.date(from: block.startedAt) else { return "" }
        let elapsed = now.timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: Spacing.section) {
                // Status
                HStack(spacing: Spacing.standard) {
                    Circle()
                        .fill(agentColor)
                        .frame(width: 8, height: 8)

                    Text("Tracking Changes")
                        .font(Typ.body.weight(.medium))

                    Text("—")
                        .foregroundStyle(.tertiary)

                    Text(block.agent == .codex ? "Codex" : "Claude")
                        .font(Typ.body)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(elapsedText(at: context.date))
                        .font(Typ.numericBody)
                        .foregroundStyle(.secondary)

                    if block.modifiedFileCount > 0 || block.newFileCount > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)

                        if block.modifiedFileCount > 0 {
                            Text("\(block.modifiedFileCount) modified")
                                .font(Typ.body)
                                .foregroundStyle(.secondary)
                        }
                        if block.newFileCount > 0 {
                            Text("\(block.newFileCount) new")
                                .font(Typ.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if block.isPaused {
                        Text("· Paused")
                            .font(Typ.body.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: Spacing.standard) {
                    Button("Review Changes", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .tint(agentColor)
                        .controlSize(.small)

                    Button(block.isPaused ? "Resume Access" : "Pause Access") {
                        onPause()
                    }
                    .controlSize(.small)

                    Button("Stop Now") {
                        showStopConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.edge)
            .padding(.vertical, Spacing.standard)
            .background(.regularMaterial)
            .alert("Stop tracking changes?", isPresented: $showStopConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Discard Changes", role: .destructive, action: onStop)
            } message: {
                Text("All changes since baseline will be discarded. This cannot be undone.")
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tracking changes for \(block.agent == .codex ? "Codex" : "Claude")")
        }
    }
}
