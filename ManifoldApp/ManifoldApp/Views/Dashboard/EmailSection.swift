import SwiftUI

struct EmailSection: View {
    @Environment(ManifoldStore.self) var store

    var body: some View {
        Section("Emails") {
            if let c = store.emailClassification {
                LabeledContent("Shared with agents") {
                    Text("\(c.shared)").foregroundStyle(.green).monospacedDigit()
                }
                LabeledContent("Auto-hidden") {
                    Text("\(c.autoHidden)").foregroundStyle(.orange).monospacedDigit()
                }
            } else {
                Text("Not configured. Manage in Settings.")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
