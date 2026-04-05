import SwiftUI
import ManifoldKit

struct EmailRow: View {
    @Environment(ManifoldStore.self) var store
    let email: CachedEmail
    let isSelected: Bool

    private var isShared: Bool { email.isShared }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(spacing: Spacing.section) {
                ColorIndicator(color: isShared ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(email.sender)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(email.dateReceived)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(email.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(email.account) / \(email.mailbox)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: Spacing.standard) {
                Button {
                    store.toggleEmailSelection(messageID: email.messageID)
                } label: {
                    Label(isSelected ? "Selected for Session" : "Select for Session", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .disabled(!isShared)

                Spacer()

                Button(action: toggleShared) {
                    Text(isShared ? "Shared" : "Hidden")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isShared ? .green : .orange)
                        .padding(.horizontal, Spacing.standard)
                        .padding(.vertical, Spacing.tight)
                        .background(isShared ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.tight)
    }

    private func toggleShared() {
        Task {
            if isShared {
                await store.hideEmail(messageID: email.messageID)
            } else {
                await store.overrideEmailToShared(messageID: email.messageID)
            }
        }
    }
}
