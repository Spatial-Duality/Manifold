import SwiftUI
import ManifoldKit

/// Right-side drawer wrapping ActivityView internals.
/// Replaces the Inspector panel when open. Accessible from any tab
/// via "View Activity →" links or ⌘⇧A.
struct ActivityDrawer: View {
    @Environment(ManifoldStore.self) var store
    @Binding var isPresented: Bool
    var agentFilter: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                    .font(.title3.weight(.medium))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(Spacing.edge)

            Divider()

            // Activity content (reuses existing ActivityView)
            ActivityView()
                .environment(store)
        }
        .frame(minWidth: 300, idealWidth: 360)
    }
}
