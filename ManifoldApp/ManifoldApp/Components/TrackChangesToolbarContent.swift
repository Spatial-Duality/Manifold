import SwiftUI
import ManifoldKit

/// Toolbar-integrated track changes indicator.
/// Replaces the VStack banner with native toolbar items.
struct TrackChangesToolbarContent: View {
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
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(agentColor)
                .frame(width: 6, height: 6)

            Text("Tracking")
                .font(.caption.weight(.medium))

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(elapsedText(at: context.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if block.modifiedFileCount > 0 {
                Text("\(block.modifiedFileCount) modified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Review Changes", action: onFinish)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(agentColor)

            Button(block.isPaused ? "Resume" : "Pause", action: onPause)
                .controlSize(.small)

            Button("Stop", role: .destructive) { showStopConfirmation = true }
                .controlSize(.small)
        }
        .confirmationDialog("Stop tracking changes?", isPresented: $showStopConfirmation) {
            Button("Discard Changes", role: .destructive, action: onStop)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All changes since baseline will be discarded.")
        }
    }
}
