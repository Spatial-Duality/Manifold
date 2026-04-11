import SwiftUI
import ManifoldKit

struct StorageSettingsPane: View {
    @Environment(ManifoldStore.self) var store
    @State private var gcResult: Int?
    @State private var integrityResult: Bool?

    var body: some View {
        Form {
            Section("Database") {
                LabeledContent("Location") {
                    HStack(spacing: Spacing.tight) {
                        Text(ManifoldStore.storeURL.path)
                            .font(Typ.mono)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ManifoldStore.storeURL.path)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }
                LabeledContent("Blob storage") {
                    Text(ByteCountFormatter.string(fromByteCount: store.storageUsed, countStyle: .file))
                        .monospacedDigit()
                }
                LabeledContent("Versions tracked") {
                    Text("\(store.allTrackedFiles.count) files")
                        .monospacedDigit()
                }
            }

            Section("Maintenance") {
                HStack {
                    Button("Clean Up Storage") {
                        Task {
                            gcResult = await store.runGarbageCollection()
                        }
                    }
                    .controlSize(.small)

                    if let gc = gcResult {
                        Text(gc > 0 ? "Removed \(gc) orphaned blobs" : "Nothing to clean up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Verify Database") {
                        Task { integrityResult = await store.runIntegrityCheck() }
                    }
                    .controlSize(.small)

                    if let ok = integrityResult {
                        Label(ok ? "Database OK" : "Issues found", systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(ok ? .green : .orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Text("Manifold \(Bundle.main.shortVersionString)")
                .font(Typ.caption)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }
}

extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
