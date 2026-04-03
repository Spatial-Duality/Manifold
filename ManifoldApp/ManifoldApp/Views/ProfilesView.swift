import SwiftUI
import ManifoldKit

struct ProfilesView: View {
    @EnvironmentObject var appState: AppState
    @State private var profiles: [NamedProfile] = []
    @State private var selectedProfileID: String = "work"

    var body: some View {
        NavigationStack {
            Form {
                // Preset selection
                Section("Quick Presets") {
                    Picker("Active preset", selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            Label(profile.name, systemImage: profile.icon)
                                .tag(profile.id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(appState.hasActiveRun)
                }

                if appState.hasActiveRun {
                    Section {
                        Label("End current access before switching profiles", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                // Selected profile details
                if let profile = profiles.first(where: { $0.id == selectedProfileID }) {
                    Section("File Sources") {
                        if profile.sourcePaths.isEmpty {
                            Text("No file sources. Add sources in the Sources tab first.")
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(profile.sourcePaths, id: \.self) { path in
                                Label(path, systemImage: "folder")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    Section("Email") {
                        LabeledContent("Include emails") {
                            Text(profile.includeEmails ? "Yes (filtered by rules)" : "No")
                                .foregroundStyle(profile.includeEmails ? .green : .secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Profiles")
            .onAppear { loadProfiles() }
        }
    }

    private func loadProfiles() {
        let manager = ProfileManager(baseURL: AppState.manifoldWorkspacesURL())
        let sourcePaths = appState.sources.map { $0.path }
        profiles = manager.seedDefaults(availableSources: sourcePaths)
        if profiles.isEmpty {
            profiles = manager.allProfiles()
        }
    }
}

#Preview("Profiles") {
    ProfilesView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
