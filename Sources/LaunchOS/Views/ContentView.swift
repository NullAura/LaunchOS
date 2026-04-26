import AppKit
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
                        Color.clear
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
                            openFolder: store.openFolder,
                            beginDragging: store.beginDragging,
                            dropOnPageItem: store.dropDraggedItem,
                            dropOnPagePosition: store.dropDraggedItem
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
                    reveal: store.revealInFinder,
                    beginDragging: store.beginDragging,
                    dropOnFolderApp: store.dropDraggedFolderApp,
                    dropIntoFolder: store.dropDraggedItemIntoFolder,
                    dropOutOfFolder: {
                        guard store.pages.indices.contains(selectedPage) else {
                            return
                        }

                        store.dropDraggedItemOutOfFolder(toPageID: store.pages[selectedPage].id)
                    }
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
    @State private var isSearchHovered = false

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                SearchTextField(
                    text: $store.searchText,
                    placeholder: "搜索",
                    isFocused: searchFocused
                )
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(isSearchHovered ? 1.055 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering in
                isSearchHovered = hovering
            }
            .onTapGesture {
                searchFocused.wrappedValue = false
                DispatchQueue.main.async {
                    searchFocused.wrappedValue = true
                }
            }
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.78, blendDuration: 0.08), value: isSearchHovered)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = ClickFocusableTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.cell?.sendsActionOnEndEditing = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard isFocused.wrappedValue,
              let window = textField.window,
              window.firstResponder !== textField.currentEditor() else {
            return
        }

        DispatchQueue.main.async {
            window.makeFirstResponder(textField)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }
    }
}

private final class ClickFocusableTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private struct PageFooterView: View {
    let pages: [LaunchPage]
    @Binding var selectedPage: Int
    @State private var hoveredPage: Int?

    var body: some View {
        VStack(spacing: 10) {
            if pages.count > 1 {
                HStack(spacing: 9) {
                    ForEach(pages.indices, id: \.self) { index in
                        PageIndicatorDot(
                            isSelected: selectedPage == index,
                            isHovered: hoveredPage == index
                        ) {
                            selectedPage = index
                        }
                        .onHover { hovering in
                            if hovering {
                                hoveredPage = index
                            } else if hoveredPage == index {
                                hoveredPage = nil
                            }
                        }
                        .help(pages[index].title)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct PageIndicatorDot: View {
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.primary.opacity(opacity))
                .frame(width: baseSize, height: baseSize)
                .scaleEffect(scale)
                .shadow(
                    color: .primary.opacity(isHovered ? 0.2 : 0),
                    radius: isHovered ? 4 : 0,
                    y: 1
                )
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.08), value: isHovered)
        .animation(.smooth(duration: 0.18), value: isSelected)
    }

    private var opacity: Double {
        if isSelected {
            return isHovered ? 0.95 : 0.86
        }

        return isHovered ? 0.56 : 0.28
    }

    private var baseSize: CGFloat {
        isSelected ? 7.5 : 7
    }

    private var scale: CGFloat {
        if isHovered {
            return isSelected ? 1.45 : 1.6
        }

        return isSelected ? 1.08 : 1
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
