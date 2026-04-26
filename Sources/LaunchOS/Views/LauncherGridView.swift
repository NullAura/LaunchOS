import AppKit
import SwiftUI

struct PagedLauncherView: View {
    let pages: [LaunchPage]
    @Binding var selectedPage: Int
    let isPagingEnabled: Bool
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void
    let openFolder: (LaunchFolder) -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = max(geometry.size.width, 1)

            ZStack {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { _, page in
                        LaunchItemGrid(
                            items: page.items,
                            geometry: geometry,
                            launchingAppID: launchingAppID,
                            launch: launch,
                            reveal: reveal,
                            openFolder: openFolder
                        )
                        .frame(width: pageWidth, height: geometry.size.height)
                    }
                }
                .offset(x: -CGFloat(selectedPage) * pageWidth + dragOffset)
                .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.12), value: selectedPage)

                PageStepButton(systemName: "chevron.left") {
                    moveToPage(max(selectedPage - 1, 0))
                }
                .disabled(selectedPage == 0)
                .opacity(selectedPage == 0 ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)

                PageStepButton(systemName: "chevron.right") {
                    moveToPage(min(selectedPage + 1, pages.count - 1))
                }
                .disabled(selectedPage >= pages.count - 1)
                .opacity(selectedPage >= pages.count - 1 ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .background(
                PageInputBridge(
                    isEnabled: isPagingEnabled,
                    pageWidth: pageWidth,
                    selectedPage: selectedPage,
                    canMovePrevious: selectedPage > 0,
                    canMoveNext: selectedPage < pages.count - 1,
                    dragChanged: { translation in
                        guard isPagingEnabled else {
                            return
                        }

                        dragOffset = resistedTranslation(
                            translation,
                            selectedPage: selectedPage,
                            pageCount: pages.count
                        )
                    },
                    dragEnded: { translation, velocity in
                        guard isPagingEnabled else {
                            dragOffset = 0
                            return
                        }

                        finishDrag(translation: translation, velocity: velocity, pageWidth: pageWidth)
                    },
                    movePrevious: { moveToPage(max(selectedPage - 1, 0)) },
                    moveNext: { moveToPage(min(selectedPage + 1, pages.count - 1)) }
                )
            )
        }
    }

    private func finishDrag(translation: CGFloat, velocity: CGFloat, pageWidth: CGFloat) {
        let distanceThreshold = pageWidth * 0.14
        let velocityThreshold: CGFloat = 720
        var nextPage = selectedPage

        if translation < -distanceThreshold || velocity < -velocityThreshold {
            nextPage = min(selectedPage + 1, pages.count - 1)
        } else if translation > distanceThreshold || velocity > velocityThreshold {
            nextPage = max(selectedPage - 1, 0)
        }

        moveToPage(nextPage)
    }

    private func moveToPage(_ page: Int) {
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.12)) {
            selectedPage = page
            dragOffset = 0
        }
    }

    private func resistedTranslation(_ translation: CGFloat, selectedPage: Int, pageCount: Int) -> CGFloat {
        if selectedPage == 0 && translation > 0 {
            return translation * 0.22
        }

        if selectedPage == pageCount - 1 && translation < 0 {
            return translation * 0.22
        }

        return translation
    }
}

struct SearchResultsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        let apps = store.searchResults

        Group {
            if apps.isEmpty {
                ContentUnavailableView("没有匹配结果", systemImage: "magnifyingglass")
            } else {
                LaunchAppGrid(
                    apps: apps,
                    spacingScale: 1,
                    launchingAppID: store.launchingAppID,
                    launch: store.launch,
                    reveal: store.revealInFinder
                )
            }
        }
    }
}

struct FolderOverlayView: View {
    let folder: LaunchFolder
    let close: () -> Void
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = min(720, max(500, geometry.size.width * 0.36))
            let height = min(720, max(520, geometry.size.height * 0.58))

            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .transition(.opacity)

                VStack(spacing: 16) {
                    Text(folder.title)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)

                    LaunchAppGrid(
                        apps: folder.apps,
                        spacingScale: 0.92,
                        mode: .folder,
                        launchingAppID: launchingAppID,
                        launch: launch,
                        reveal: reveal
                    )
                }
                .frame(width: width, height: height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
            }
        }
    }
}

private struct LaunchItemGrid: View {
    let items: [LaunchItem]
    let geometry: GeometryProxy
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void
    let openFolder: (LaunchFolder) -> Void

    var body: some View {
        let metrics = GridMetrics(size: geometry.size, itemCount: items.count)
        let rows = pageRows(items, columns: metrics.columnCount, rows: metrics.targetRowCount)

        VStack(spacing: metrics.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: metrics.columnSpacing) {
                    ForEach(row.indices, id: \.self) { index in
                        if let item = row[index] {
                            launchItemView(item, metrics: metrics)
                        } else {
                            Color.clear
                                .frame(width: metrics.tileWidth, height: metrics.tileHeight)
                        }
                    }
                }
                .frame(width: metrics.gridWidth, alignment: .leading)
            }
        }
        .frame(width: metrics.gridWidth, height: metrics.gridHeight, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func launchItemView(_ item: LaunchItem, metrics: GridMetrics) -> some View {
        switch item {
        case .app(let app):
            AppTile(
                app: app,
                tileWidth: metrics.tileWidth,
                tileHeight: metrics.tileHeight,
                iconSize: metrics.iconSize,
                labelSpacing: metrics.labelSpacing,
                labelHeight: metrics.labelHeight,
                labelFontSize: metrics.labelFontSize,
                isLaunching: launchingAppID == app.id,
                launch: launch,
                reveal: reveal
            )
        case .folder(let folder):
            FolderTile(
                folder: folder,
                tileWidth: metrics.tileWidth,
                tileHeight: metrics.tileHeight,
                iconSize: metrics.iconSize,
                labelSpacing: metrics.labelSpacing,
                labelHeight: metrics.labelHeight,
                labelFontSize: metrics.labelFontSize,
                open: openFolder
            )
        }
    }

    private func pageRows(_ items: [LaunchItem], columns: Int, rows: Int) -> [[LaunchItem?]] {
        let capacity = max(columns * rows, 1)
        let pageItems = Array(items.prefix(capacity))

        return (0..<rows).map { rowIndex in
            (0..<columns).map { columnIndex in
                let itemIndex = rowIndex * columns + columnIndex
                return itemIndex < pageItems.count ? pageItems[itemIndex] : nil
            }
        }
    }
}

private struct LaunchAppGrid: View {
    let apps: [LaunchApp]
    let spacingScale: CGFloat
    var mode: GridMetrics.Mode = .list
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(size: geometry.size, itemCount: apps.count, spacingScale: spacingScale, mode: mode)

            ScrollView {
                LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                    ForEach(apps) { app in
                        AppTile(
                            app: app,
                            tileWidth: metrics.tileWidth,
                            tileHeight: metrics.tileHeight,
                            iconSize: metrics.iconSize,
                            labelSpacing: metrics.labelSpacing,
                            labelHeight: metrics.labelHeight,
                            labelFontSize: metrics.labelFontSize,
                            isLaunching: launchingAppID == app.id,
                            launch: launch,
                            reveal: reveal
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct AppTile: View {
    let app: LaunchApp
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let labelSpacing: CGFloat
    let labelHeight: CGFloat
    let labelFontSize: CGFloat
    let isLaunching: Bool
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void

    var body: some View {
        Button {
            launch(app)
        } label: {
            VStack(spacing: labelSpacing) {
                Image(nsImage: IconProvider.shared.icon(for: app))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)

                Text(app.title)
                    .font(.system(size: labelFontSize))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: tileWidth, height: labelHeight, alignment: .top)
            }
            .frame(width: tileWidth, height: tileHeight)
            .scaleEffect(isLaunching ? 1.18 : 1)
            .opacity(isLaunching ? 0 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .animation(.smooth(duration: 0.2), value: isLaunching)
        .contextMenu {
            Button("打开") {
                launch(app)
            }

            Button("在 Finder 中显示") {
                reveal(app)
            }

            if let bundleIdentifier = app.bundleIdentifier {
                Text(bundleIdentifier)
            }
        }
        .help(app.bundleIdentifier ?? app.title)
    }
}

private struct FolderTile: View {
    let folder: LaunchFolder
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let labelSpacing: CGFloat
    let labelHeight: CGFloat
    let labelFontSize: CGFloat
    let open: (LaunchFolder) -> Void

    var body: some View {
        Button {
            open(folder)
        } label: {
            VStack(spacing: labelSpacing) {
                FolderPreview(apps: Array(folder.apps.prefix(9)), iconSize: iconSize)
                    .frame(width: iconSize, height: iconSize)

                Text(folder.title)
                    .font(.system(size: labelFontSize))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: tileWidth, height: labelHeight, alignment: .top)
            }
            .frame(width: tileWidth, height: tileHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folder.title)
    }
}

private struct FolderPreview: View {
    let apps: [LaunchApp]
    let iconSize: CGFloat

    var body: some View {
        let cornerRadius = iconSize * 0.24
        let spacing = iconSize * 0.05
        let padding = iconSize * 0.13
        let miniIconSize = (iconSize - padding * 2 - spacing * 2) / 3

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thickMaterial)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(miniIconSize), spacing: spacing), count: 3),
                spacing: spacing
            ) {
                ForEach(apps.prefix(9)) { app in
                    Image(nsImage: IconProvider.shared.icon(for: app))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: miniIconSize, height: miniIconSize)
                }
            }
            .padding(padding)
        }
    }
}

private struct PageStepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 46, height: 68)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GridMetrics {
    let columns: [GridItem]
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let labelSpacing: CGFloat
    let labelHeight: CGFloat
    let labelFontSize: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let columnCount: Int
    let horizontalPadding: CGFloat
    let gridWidth: CGFloat
    let gridHeight: CGFloat
    let targetRowCount: Int

    enum Mode {
        case page
        case list
        case folder
    }

    init(size: CGSize, itemCount: Int, spacingScale: CGFloat = 1, mode: Mode = .page) {
        let widthBasedColumns = max(3, min(7, Int(size.width / 126)))
        let columnCount: Int
        let targetRows: Int

        switch mode {
        case .page:
            columnCount = size.width >= 900 ? 7 : widthBasedColumns
            targetRows = size.height >= 700 ? 5 : 4
        case .list:
            columnCount = min(widthBasedColumns, max(itemCount, 1))
            targetRows = max(1, Int(ceil(Double(max(itemCount, 1)) / Double(max(columnCount, 1)))))
        case .folder:
            columnCount = min(4, max(2, min(widthBasedColumns, max(itemCount, 1))))
            targetRows = max(1, Int(ceil(Double(max(itemCount, 1)) / Double(max(columnCount, 1)))))
        }

        let targetWidthFraction: CGFloat
        if size.width >= 3000 {
            targetWidthFraction = 0.80
        } else if size.width >= 1800 {
            targetWidthFraction = 0.76
        } else if size.width >= 1000 {
            targetWidthFraction = 0.72
        } else {
            targetWidthFraction = 0.86
        }

        let targetHeightFraction: CGFloat
        if size.height >= 1800 {
            targetHeightFraction = 0.76
        } else if size.height >= 1000 {
            targetHeightFraction = 0.72
        } else {
            targetHeightFraction = 0.78
        }

        let tileWidthRatio: CGFloat = 1.48
        let labelSpacingRatio: CGFloat = 0.10
        let labelHeightRatio: CGFloat = 0.42
        let columnSpacingRatio: CGFloat = 0.74
        let rowSpacingRatio: CGFloat = 0.58
        let tileHeightRatio = 1 + labelSpacingRatio + labelHeightRatio
        let widthCoefficient = CGFloat(columnCount) * tileWidthRatio
            + CGFloat(max(columnCount - 1, 0)) * columnSpacingRatio
        let heightCoefficient = CGFloat(targetRows) * tileHeightRatio
            + CGFloat(max(targetRows - 1, 0)) * rowSpacingRatio
        let iconSizeFromWidth = size.width * targetWidthFraction / widthCoefficient
        let iconSizeFromHeight = size.height * targetHeightFraction / heightCoefficient
        let shortSide = min(size.width, size.height)
        let proportionalMinimum = shortSide * 0.052
        let proportionalMaximum = shortSide * (mode == .folder ? 0.18 : 0.105)
        let resolvedIconSize = min(max(min(iconSizeFromWidth, iconSizeFromHeight), proportionalMinimum), proportionalMaximum)

        self.iconSize = resolvedIconSize
        self.tileWidth = resolvedIconSize * tileWidthRatio
        self.labelSpacing = resolvedIconSize * labelSpacingRatio
        self.labelHeight = resolvedIconSize * labelHeightRatio
        self.labelFontSize = resolvedIconSize * 0.115
        self.tileHeight = resolvedIconSize * tileHeightRatio
        self.rowSpacing = resolvedIconSize * rowSpacingRatio * spacingScale
        self.columnSpacing = resolvedIconSize * columnSpacingRatio * spacingScale
        self.columnCount = columnCount
        self.gridWidth = tileWidth * CGFloat(columnCount) + columnSpacing * CGFloat(max(columnCount - 1, 0))
        self.gridHeight = tileHeight * CGFloat(targetRows) + rowSpacing * CGFloat(max(targetRows - 1, 0))
        self.targetRowCount = targetRows
        self.horizontalPadding = max(24, (size.width - gridWidth) / 2)
        self.columns = Array(repeating: GridItem(.fixed(tileWidth), spacing: columnSpacing), count: columnCount)
    }
}

// SwiftUI drag gestures can miss transparent space after page offsets; keep paging input scoped to the full page view.
private struct PageInputBridge: NSViewRepresentable {
    let isEnabled: Bool
    let pageWidth: CGFloat
    let selectedPage: Int
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (CGFloat, CGFloat) -> Void
    let movePrevious: () -> Void
    let moveNext: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor(attachedTo: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.pageWidth = pageWidth
        context.coordinator.canMovePrevious = canMovePrevious
        context.coordinator.canMoveNext = canMoveNext
        context.coordinator.dragChanged = dragChanged
        context.coordinator.dragEnded = dragEnded
        context.coordinator.movePrevious = movePrevious
        context.coordinator.moveNext = moveNext
        context.coordinator.updateSelectedPage(selectedPage)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled = false
        var pageWidth: CGFloat = 1
        var canMovePrevious = false
        var canMoveNext = false
        var dragChanged: (CGFloat) -> Void = { _ in }
        var dragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        var movePrevious: () -> Void = {}
        var moveNext: () -> Void = {}

        private weak var view: NSView?
        private var monitor: Any?
        private var selectedPage = 0
        private var accumulatedScrollDeltaX: CGFloat = 0
        private var lastScrollMoveDate = Date.distantPast
        private var isTrackingDrag = false
        private var didBeginPagingDrag = false
        private var accumulatedDragX: CGFloat = 0
        private var accumulatedDragY: CGFloat = 0
        private var dragStartDate = Date.distantPast

        deinit {
            removeMonitor()
        }

        func installMonitor(attachedTo view: NSView) {
            self.view = view
            guard monitor == nil else {
                return
            }

            let mask: NSEvent.EventTypeMask = [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func updateSelectedPage(_ page: Int) {
            guard selectedPage != page else {
                return
            }

            selectedPage = page
            resetScrollState()
            resetDragState()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled else {
                resetScrollState()
                cancelDrag()
                return event
            }

            switch event.type {
            case .scrollWheel:
                return handleScroll(event)
            case .leftMouseDown:
                return handleMouseDown(event)
            case .leftMouseDragged:
                return handleMouseDragged(event)
            case .leftMouseUp:
                return handleMouseUp(event)
            default:
                return event
            }
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard isEventInsideBridge(event) else {
                return event
            }

            let shouldResetAtEnd = event.phase == .ended
                || event.phase == .cancelled
                || event.momentumPhase == .ended
                || event.momentumPhase == .cancelled
            defer {
                if shouldResetAtEnd {
                    resetScrollState()
                }
            }

            if event.phase == .began || event.momentumPhase == .began {
                resetScrollState()
            }

            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            guard abs(horizontal) > max(1.2, abs(vertical) * 1.2) else {
                return event
            }

            accumulatedScrollDeltaX += horizontal

            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? min(18, max(8, pageWidth * 0.004)) : 2
            let now = Date()
            guard abs(accumulatedScrollDeltaX) >= threshold,
                  now.timeIntervalSince(lastScrollMoveDate) > 0.22 else {
                return nil
            }

            if accumulatedScrollDeltaX > 0, canMoveNext {
                moveNext()
                lastScrollMoveDate = now
            } else if accumulatedScrollDeltaX < 0, canMovePrevious {
                movePrevious()
                lastScrollMoveDate = now
            }

            accumulatedScrollDeltaX = 0
            return nil
        }

        private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
            guard isEventInsideBridge(event) else {
                cancelDrag()
                return event
            }

            isTrackingDrag = true
            didBeginPagingDrag = false
            accumulatedDragX = 0
            accumulatedDragY = 0
            dragStartDate = Date()
            return event
        }

        private func handleMouseDragged(_ event: NSEvent) -> NSEvent? {
            if !isTrackingDrag {
                guard isEventInsideBridge(event) else {
                    return event
                }

                isTrackingDrag = true
                dragStartDate = Date()
            }

            accumulatedDragX += event.deltaX
            accumulatedDragY += event.deltaY

            if didBeginPagingDrag || abs(accumulatedDragX) > max(4, abs(accumulatedDragY) * 1.15) {
                didBeginPagingDrag = true
                dragChanged(accumulatedDragX)
                return nil
            }

            return event
        }

        private func handleMouseUp(_ event: NSEvent) -> NSEvent? {
            guard isTrackingDrag else {
                return event
            }

            let shouldConsume = didBeginPagingDrag
            let elapsed = max(Date().timeIntervalSince(dragStartDate), 0.001)
            let velocity = accumulatedDragX / CGFloat(elapsed)
            let translation = accumulatedDragX

            if didBeginPagingDrag {
                dragEnded(translation, velocity)
            }

            resetDragState()
            return shouldConsume ? nil : event
        }

        private func isEventInsideBridge(_ event: NSEvent) -> Bool {
            guard let view,
                  let window = view.window,
                  event.window === window else {
                return false
            }

            let point = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(point)
        }

        private func resetScrollState() {
            accumulatedScrollDeltaX = 0
        }

        private func cancelDrag() {
            if didBeginPagingDrag {
                dragChanged(0)
            }

            resetDragState()
        }

        private func resetDragState() {
            isTrackingDrag = false
            didBeginPagingDrag = false
            accumulatedDragX = 0
            accumulatedDragY = 0
            dragStartDate = .distantPast
        }
    }
}
