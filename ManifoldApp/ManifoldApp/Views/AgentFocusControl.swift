import SwiftUI

/// Reusable segmented control: Claude | Codex | Compare.
/// Drives single-column vs. dual-column table layout in Files and Emails tabs.
/// Self-describing — no external label needed (1.7/2.5).
struct AgentFocusControl: View {
    @Binding var focus: AgentFocus

    var body: some View {
        Picker(selection: $focus) {
            Text("Claude").tag(AgentFocus.claude)
            Text("Codex").tag(AgentFocus.codex)
            Text("Compare").tag(AgentFocus.compare)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .controlSize(.small)
        .accessibilityLabel("Agent focus")
        .accessibilityHint("Shows \(focus.displayName) access columns in the table")
    }
}
