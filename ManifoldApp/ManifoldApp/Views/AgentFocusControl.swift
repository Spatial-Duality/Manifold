import SwiftUI

/// Reusable segmented control: Claude | Codex | Compare.
/// Drives single-column vs. dual-column table layout in Files and Emails tabs.
/// Uses the agent's semantic color for the selected segment.
struct AgentFocusControl: View {
    @Binding var focus: AgentFocus

    var body: some View {
        Picker("Agent", selection: $focus) {
            Text("Claude").tag(AgentFocus.claude)
            Text("Codex").tag(AgentFocus.codex)
            Text("Compare").tag(AgentFocus.compare)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .controlSize(.small)
        .accessibilityLabel("Agent focus")
        .accessibilityHint("Shows \(focus.displayName) access columns in the table")
    }
}
