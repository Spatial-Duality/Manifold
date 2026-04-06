import SwiftUI

struct AgentBadge: View {
    let agent: String

    private var color: Color {
        switch agent.lowercased() {
        case "codex": .purple
        default: .blue
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(agent).font(.caption.weight(.medium))
        }
    }
}
