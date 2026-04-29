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
    @State private var searchFocusRequest = 0

    var body: some View {
        let metrics = SearchFieldMetrics.current

        HStack {
            NativeSearchField(
                text: $store.searchText,
                placeholder: "搜索",
                isFocused: searchFocused,
                focusRequest: searchFocusRequest,
                fontSize: metrics.fontSize
            )
            .frame(height: metrics.controlHeight)
            .padding(.horizontal, metrics.horizontalInset)
            .padding(.vertical, metrics.verticalInset)
            .frame(width: metrics.width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .scaleEffect(isSearchHovered ? metrics.hoverScale : 1)
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .onHover { hovering in
                isSearchHovered = hovering
            }
            .simultaneousGesture(TapGesture().onEnded(requestSearchFocus))
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.78, blendDuration: 0.08), value: isSearchHovered)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
    }

    private func requestSearchFocus() {
        searchFocused.wrappedValue = true
        searchFocusRequest += 1
    }
}

private struct SearchFieldMetrics {
    let screenSize: CGSize

    static var current: SearchFieldMetrics {
        SearchFieldMetrics(screenSize: NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900))
    }

    private var scale: CGFloat {
        min(max(screenSize.width / 1920, 0.94), 1.18)
    }

    var width: CGFloat {
        min(max(screenSize.width * 0.145, 260), 340)
    }

    var horizontalInset: CGFloat {
        12 * scale
    }

    var verticalInset: CGFloat {
        6 * scale
    }

    var controlHeight: CGFloat {
        22 * scale
    }

    var fontSize: CGFloat {
        13 * scale
    }

    var cornerRadius: CGFloat {
        8 * scale
    }

    var hoverScale: CGFloat {
        1 + (0.052 * scale)
    }

    var topPadding: CGFloat {
        min(max(screenSize.height * 0.038, 36), 54)
    }

    var bottomPadding: CGFloat {
        min(max(screenSize.height * 0.014, 13), 18)
    }
}

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let focusRequest: Int
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = FocusAwareSearchField()
        searchField.delegate = context.coordinator
        searchField.placeholderString = placeholder
        searchField.stringValue = text
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.maximumRecents = 0
        searchField.recentsAutosaveName = nil
        searchField.font = .systemFont(ofSize: fontSize)
        searchField.cell?.wraps = false
        searchField.cell?.usesSingleLineMode = true
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self

        if searchField.stringValue != text {
            searchField.stringValue = text
        }

        if searchField.placeholderString != placeholder {
            searchField.placeholderString = placeholder
        }

        if searchField.font?.pointSize != fontSize {
            searchField.font = .systemFont(ofSize: fontSize)
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            focus(searchField, selectIfNeeded: true)
            return
        }

        guard isFocused.wrappedValue else {
            return
        }

        focus(searchField, selectIfNeeded: false)
    }

    private func focus(_ searchField: NSSearchField, selectIfNeeded: Bool) {
        DispatchQueue.main.async {
            guard let window = searchField.window else {
                return
            }

            if window.firstResponder !== searchField.currentEditor() {
                window.makeFirstResponder(searchField)
            }

            if selectIfNeeded {
                searchField.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        var lastFocusRequest: Int

        init(_ parent: NativeSearchField) {
            self.parent = parent
            self.lastFocusRequest = parent.focusRequest
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }

            parent.text = searchField.stringValue
        }
    }
}

private final class FocusAwareSearchField: NSSearchField {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        DispatchQueue.main.async {
            self.selectText(nil)
        }
    }
}

private struct PageFooterView: View {
    let pages: [LaunchPage]
    @Binding var selectedPage: Int
    @State private var hoveredPage: Int?
    @State private var isStripHovered = false

    var body: some View {
        let metrics = PageFooterMetrics.current

        VStack(spacing: 10) {
            if pages.count > 1 {
                HStack(spacing: metrics.dotSpacing) {
                    ForEach(pages.indices, id: \.self) { index in
                        PageIndicatorDot(
                            isSelected: selectedPage == index,
                            isHovered: hoveredPage == index,
                            metrics: metrics
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
                .padding(.horizontal, metrics.stripHorizontalPadding)
                .padding(.vertical, metrics.stripVerticalPadding)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(isStripHovered ? 0.88 : 0.72)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(isStripHovered ? 0.28 : 0.16), lineWidth: metrics.strokeWidth)
                }
                .scaleEffect(isStripHovered ? metrics.stripHoverScale : 1)
                .shadow(
                    color: .black.opacity(isStripHovered ? 0.18 : 0.12),
                    radius: isStripHovered ? metrics.stripHoverShadowRadius : metrics.shadowRadius,
                    y: metrics.shadowYOffset
                )
                .contentShape(Capsule(style: .continuous))
                .onHover { hovering in
                    isStripHovered = hovering
                }
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.78, blendDuration: 0.08), value: isStripHovered)
            }
        }
        .padding(.horizontal, metrics.outerHorizontalPadding)
        .padding(.bottom, metrics.bottomPadding)
    }
}

private struct PageIndicatorDot: View {
    let isSelected: Bool
    let isHovered: Bool
    let metrics: PageFooterMetrics
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
                .frame(width: metrics.hitSize, height: metrics.hitSize)
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
        isSelected ? metrics.selectedDotSize : metrics.dotSize
    }

    private var scale: CGFloat {
        if isHovered {
            return isSelected ? 1.45 : 1.6
        }

        return isSelected ? 1.08 : 1
    }
}

private struct PageFooterMetrics {
    let screenSize: CGSize

    static var current: PageFooterMetrics {
        PageFooterMetrics(screenSize: NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900))
    }

    private var scale: CGFloat {
        min(max(screenSize.width / 1920, 0.92), 1.18)
    }

    var dotSize: CGFloat {
        7 * scale
    }

    var selectedDotSize: CGFloat {
        7.5 * scale
    }

    var hitSize: CGFloat {
        20 * scale
    }

    var dotSpacing: CGFloat {
        9 * scale
    }

    var stripHorizontalPadding: CGFloat {
        10 * scale
    }

    var stripVerticalPadding: CGFloat {
        3 * scale
    }

    var strokeWidth: CGFloat {
        0.7 * scale
    }

    var shadowRadius: CGFloat {
        10 * scale
    }

    var stripHoverShadowRadius: CGFloat {
        14 * scale
    }

    var shadowYOffset: CGFloat {
        4 * scale
    }

    var stripHoverScale: CGFloat {
        1 + (0.035 * scale)
    }

    var outerHorizontalPadding: CGFloat {
        24 * scale
    }

    var bottomPadding: CGFloat {
        min(max(screenSize.height * 0.022, 22), 34)
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
