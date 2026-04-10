import SwiftUI
import ManifoldKit

/// Right-side drawer wrapping ActivityView internals.
/// Accessible from any tab via "View Activity →" links or ⌘⇧A.
struct ActivityDrawer: View {
    @Environment(ManifoldStore.self) var store
    @Binding var isPresented: Bool
    @State private var agentFilter: AgentFilter = .all

    enum AgentFilter: String, CaseIterable {
        case all = "All"
        case claude = "Claude"
        case codex = "Codex"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                    .font(.title3.weight(.medium))

                Spacer()

                Picker("Agent", selection: $agentFilter) {
                    ForEach(AgentFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close Activity (⌘⇧A)")
                .accessibilityLabel("Close activity drawer")
            }
            .padding(Spacing.edge)

            Divider()

            // Activity content
            ActivityView()
                .environment(store)
        }
        .frame(minWidth: 300, idealWidth: 360)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
