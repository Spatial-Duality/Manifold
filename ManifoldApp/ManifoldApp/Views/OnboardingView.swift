import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, description: String)] = [
        (
            "folder.badge.plus",
            "Pick what Claude can see",
            "Select files and folders through Finder. Connect Apple Mail for email context. You choose exactly what goes in the workspace."
        ),
        (
            "play.circle",
            "Grant access, track everything",
            "Click \"Grant to Claude\" to start a tracked session. Manifold watches every file change and snapshots every version."
        ),
        (
            "arrow.uturn.backward.circle",
            "Restore any version",
            "See every modification in the timeline. Restore any previous state with one click. Your originals are never touched."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content with cross-fade transition
            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    if index == currentPage {
                        OnboardingPage(
                            icon: page.icon,
                            title: page.title,
                            description: page.description
                        )
                        .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: currentPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation bar
            HStack {
                // Back button
                Button("Back") {
                    currentPage -= 1
                }
                .buttonStyle(.bordered)
                .opacity(currentPage > 0 ? 1 : 0)
                .disabled(currentPage == 0)

                Spacer()

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                // Next / Get Started
                if currentPage < pages.count - 1 {
                    Button("Next") {
                        currentPage += 1
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
            .padding(20)
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
                .padding(.bottom, 4)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environmentObject(AppState())
        .frame(width: 500, height: 400)
}
