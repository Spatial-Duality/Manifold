import SwiftUI
import ManifoldKit

struct ShareWithCoworkSheet: View {
    @Environment(ManifoldStore.self) var store
    @Environment(\.dismiss) private var dismiss
    let emailIDs: [String]
    let onDismiss: () -> Void
    @State private var isSharing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 36))
                .foregroundStyle(.purple)

            VStack(spacing: Spacing.standard) {
                Text("Share with Cowork")
                    .font(.title3.weight(.semibold))
                Text("Share \(emailIDs.count) email\(emailIDs.count == 1 ? "" : "s") with your AI assistant. Shared emails remain accessible until you revoke access.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: Spacing.section) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    share()
                } label: {
                    if isSharing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Share")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isSharing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.large)
        .frame(width: 360)
    }

    private func share() {
        isSharing = true
        Task {
            await store.emailAccounts.shareEmails(emailIDs: emailIDs)
            onDismiss()
            dismiss()
            isSharing = false
        }
    }
}
