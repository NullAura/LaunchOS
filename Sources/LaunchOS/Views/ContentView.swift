import SwiftUI

struct ContentView: View {
    @StateObject private var store = LauncherStore()
    @SceneStorage("LaunchOS.selectedPage") private var selectedPage = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            LauncherBackdrop()

            VStack(spacing: 0) {
                HeaderView(
                    store: store,
                    searchFocused: $searchFocused
                )

                Group {
                    if store.isLoading && store.pages.isEmpty {
                        ProgressView("正在扫描")
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SearchResultsView(store: store)
                    } else if store.pages.isEmpty {
                        EmptyStateView(reload: store.reload)
                    } else {
                        PagedLauncherView(
                            pages: store.pages,
                            selectedPage: $selectedPage,
                            isPagingEnabled: store.activeFolder == nil,
                            launchingAppID: store.launchingAppID,
                            launch: store.launch,
                            reveal: store.revealInFinder,
                            openFolder: store.openFolder
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PageFooterView(
                    pages: store.pages,
                    selectedPage: $selectedPage
                )
            }

            if let folder = store.activeFolder {
                FolderOverlayView(
                    folder: folder,
                    close: store.closeFolder,
                    launchingAppID: store.launchingAppID,
                    launch: store.launch,
                    reveal: store.revealInFinder
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .center)),
                        removal: .opacity.combined(with: .scale(scale: 1.03, anchor: .center))
                    )
                )
            }
        }
        .background(WindowFullscreenBridge())
        .ignoresSafeArea()
        .opacity(store.isClosing ? 0 : 1)
        .scaleEffect(store.isClosing ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.22), value: store.isClosing)
        .animation(.smooth(duration: 0.28), value: store.activeFolder?.id)
        .focusable()
        .onExitCommand(perform: store.handleExitCommand)
        .onMoveCommand(perform: moveSelection)
        .task {
            store.loadIfNeeded()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchOSRefreshRequested)) { _ in
            store.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchOSExitRequested)) { _ in
            store.handleExitCommand()
        }
        .onChange(of: store.pages.count) { _, count in
            if count == 0 {
                selectedPage = 0
            } else if selectedPage >= count {
                selectedPage = count - 1
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard store.activeFolder == nil,
              store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              store.pages.count > 1 else {
            return
        }

        switch direction {
        case .left:
            selectedPage = max(selectedPage - 1, 0)
        case .right:
            selectedPage = min(selectedPage + 1, store.pages.count - 1)
        default:
            break
        }
    }
}

private struct LauncherBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.08),
                            Color.black.opacity(0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }
}

private struct HeaderView: View {
    @ObservedObject var store: LauncherStore
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .focused(searchFocused)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }
}

private struct PageFooterView: View {
    let pages: [LaunchPage]
    @Binding var selectedPage: Int

    var body: some View {
        VStack(spacing: 10) {
            if pages.count > 1 {
                HStack(spacing: 9) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button {
                            selectedPage = index
                        } label: {
                            Circle()
                                .fill(.primary.opacity(selectedPage == index ? 0.86 : 0.28))
                                .frame(width: 7, height: 7)
                        }
                        .buttonStyle(.plain)
                        .help(pages[index].title)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct EmptyStateView: View {
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.app")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("没有找到可启动的应用")
                .font(.headline)

            Button("重新扫描", action: reload)
        }
        .padding()
    }
}
