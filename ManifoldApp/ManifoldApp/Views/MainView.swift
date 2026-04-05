import SwiftUI
import ManifoldKit

struct MainView: View {
    @Environment(ManifoldStore.self) var store
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailContent
                .inspector(isPresented: inspectorBinding) {
                    if let path = store.inspectedFilePath {
                        VersionDetailView(filePath: path)
                            .inspectorColumnWidth(min: 320, ideal: 400, max: 500)
                    }
                }
        }
        .overlay(alignment: .top) {
            if let error = store.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") { store.lastError = nil }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.medium))
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: store.lastError)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environment(store)
        }
        .task {
            if !store.hasCompletedOnboarding { showOnboarding = true }
            await store.loadSummary()
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { store.inspectedFilePath != nil },
            set: { if !$0 { store.inspectedFilePath = nil } }
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch store.selectedSidebarItem {
            case .dashboard, nil:
                DashboardView()
            case .files:
                FilesView()
            case .activity:
                ActivityView()
            case .email:
                EmailView()
            case .versions:
                VersionsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Source", systemImage: "folder.badge.plus") {
                    store.addSourceFromPicker()
                }
            }
        }
    }
}
