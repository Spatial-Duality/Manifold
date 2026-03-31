import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            // Pages
            TabView(selection: $currentPage) {
                OnboardingPage(
                    icon: "folder.badge.plus",
                    title: "Pick what Claude can see",
                    description: "Select files and folders through Finder. Connect Apple Mail for email context. You choose exactly what goes in the workspace."
                ).tag(0)

                OnboardingPage(
                    icon: "play.circle",
                    title: "Grant access, track everything",
                    description: "Click \"Grant to Claude\" to start a tracked session. Manifold watches every file change and snapshots every version."
                ).tag(1)

                OnboardingPage(
                    icon: "arrow.uturn.backward.circle",
                    title: "Restore any version",
                    description: "See every modification in the timeline. Restore any previous state with one click. Your originals are never touched."
                ).tag(2)
            }
            .tabViewStyle(.automatic)

            // Navigation
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Page indicators
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if currentPage < 2 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Get Started") {
                        appState.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Spacer()
        }
        .padding(24)
    }
}
