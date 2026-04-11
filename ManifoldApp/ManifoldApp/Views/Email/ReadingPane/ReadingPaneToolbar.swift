import SwiftUI
import ManifoldKit

struct ReadingPaneToolbar: View {
    @Environment(ManifoldStore.self) var store
    let message: EmailMessageRecord
    @Bindable var selection: EmailSelectionModel
    @State private var showShareSheet = false

    var body: some View {
        HStack(spacing: Spacing.section) {
            Spacer()

            Button {
                Task {
                    await store.emailAccounts.updateFlagState(
                        emailID: message.emailID,
                        isFlagged: !message.isFlagged
                    )
                }
            } label: {
                Image(systemName: message.isFlagged ? "flag.fill" : "flag")
                    .foregroundStyle(message.isFlagged ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help(message.isFlagged ? "Unflag" : "Flag")

            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.borderless)
            .help("Share with Claude")

            if let path = message.emlPath {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } label: {
                    Label("Open", systemImage: "envelope")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open in default mail app")

                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, Spacing.edge)
        .padding(.vertical, Spacing.tight)
        .sheet(isPresented: $showShareSheet) {
            ShareWithCoworkSheet(
                emailIDs: [message.emailID],
                onDismiss: { showShareSheet = false }
            )
        }
    }
}
