import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PagedLauncherView: View {
    let pages: [LaunchPage]
    @Binding var selectedPage: Int
    let isPagingEnabled: Bool
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void
    let openFolder: (LaunchFolder) -> Void
    let beginDragging: (LaunchItem, String) -> Void
    let dropOnPageItem: (String, String, LaunchDropPlacement) -> Void
    let dropOnPagePosition: (String, Int) -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = max(geometry.size.width, 1)
            let itemDragTargets = currentPageItemDragTargets(in: geometry.size)

            ZStack {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { _, page in
                        LaunchItemGrid(
                            page: page,
                            geometry: geometry,
                            launchingAppID: launchingAppID,
                            launch: launch,
                            reveal: reveal,
                            openFolder: openFolder,
                            beginDragging: beginDragging,
                            dropOnPageItem: dropOnPageItem,
                            dropOnPagePosition: dropOnPagePosition
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
                    itemDragTargets: itemDragTargets,
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
                    beginItemDrag: beginDragging,
                    dropOnPageItem: dropOnPageItem,
                    dropOnPagePosition: dropOnPagePosition,
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

    private func currentPageItemDragTargets(in size: CGSize) -> [PageItemDragTarget] {
        guard pages.indices.contains(selectedPage) else {
            return []
        }

        let page = pages[selectedPage]
        let metrics = GridMetrics(size: size, itemCount: page.items.count)
        let originX = (size.width - metrics.gridWidth) / 2
        let originY = (size.height - metrics.gridHeight) / 2

        return page.items.indices.map { index in
            let row = index / metrics.columnCount
            let column = index % metrics.columnCount
            return PageItemDragTarget(
                pageID: page.id,
                item: page.items[index],
                index: index,
                rect: CGRect(
                    x: originX + CGFloat(column) * (metrics.tileWidth + metrics.columnSpacing),
                    y: originY + CGFloat(row) * (metrics.tileHeight + metrics.rowSpacing),
                    width: metrics.tileWidth,
                    height: metrics.tileHeight
                )
            )
        }
    }
}

private struct PageItemDragTarget: Equatable {
    let pageID: String
    let item: LaunchItem
    let index: Int
    let rect: CGRect
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
    let beginDragging: (LaunchApp, String) -> Void
    let dropOnFolderApp: (String, String, LaunchDropPlacement) -> Void
    let dropIntoFolder: (String) -> Void
    let dropOutOfFolder: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = min(720, max(500, geometry.size.width * 0.36))
            let height = min(720, max(520, geometry.size.height * 0.58))

            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .onDrop(
                        of: [.plainText],
                        delegate: FolderBackdropDropDelegate(drop: dropOutOfFolder)
                    )
                    .transition(.opacity)

                VStack(spacing: 16) {
                    Text(folder.title)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)

                    FolderAppGrid(
                        folderID: folder.id,
                        apps: folder.apps,
                        spacingScale: 0.92,
                        launchingAppID: launchingAppID,
                        launch: launch,
                        reveal: reveal,
                        beginDragging: beginDragging,
                        dropOnFolderApp: dropOnFolderApp,
                        dropIntoFolder: dropIntoFolder
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
    let page: LaunchPage
    let geometry: GeometryProxy
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void
    let openFolder: (LaunchFolder) -> Void
    let beginDragging: (LaunchItem, String) -> Void
    let dropOnPageItem: (String, String, LaunchDropPlacement) -> Void
    let dropOnPagePosition: (String, Int) -> Void

    var body: some View {
        let metrics = GridMetrics(size: geometry.size, itemCount: page.items.count)
        let rows = pageRows(page.items, columns: metrics.columnCount, rows: metrics.targetRowCount)

        VStack(spacing: metrics.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: metrics.columnSpacing) {
                    ForEach(row.indices, id: \.self) { index in
                        if let item = row[index] {
                            launchItemView(item, metrics: metrics)
                        } else {
                            Color.clear
                                .frame(width: metrics.tileWidth, height: metrics.tileHeight)
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [.plainText],
                                    delegate: PagePositionDropDelegate(
                                        pageID: page.id,
                                        index: rowIndex * metrics.columnCount + index,
                                        drop: dropOnPagePosition
                                    )
                                )
                        }
                    }
                }
                .frame(width: metrics.gridWidth, alignment: .leading)
            }
        }
        .frame(width: metrics.gridWidth, height: metrics.gridHeight, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(
            of: [.plainText],
            delegate: PagePositionDropDelegate(
                pageID: page.id,
                index: page.items.count,
                drop: dropOnPagePosition
            )
        )
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
                reveal: reveal,
                beginDrag: {
                    beginDragging(item, page.id)
                }
            )
            .onDrop(
                of: [.plainText],
                delegate: PageItemDropDelegate(
                    pageID: page.id,
                    targetItemID: item.id,
                    tileSize: CGSize(width: metrics.tileWidth, height: metrics.tileHeight),
                    drop: dropOnPageItem
                )
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
                open: openFolder,
                beginDrag: {
                    beginDragging(item, page.id)
                }
            )
            .onDrop(
                of: [.plainText],
                delegate: PageItemDropDelegate(
                    pageID: page.id,
                    targetItemID: item.id,
                    tileSize: CGSize(width: metrics.tileWidth, height: metrics.tileHeight),
                    drop: dropOnPageItem
                )
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

private struct FolderAppGrid: View {
    let folderID: String
    let apps: [LaunchApp]
    let spacingScale: CGFloat
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void
    let beginDragging: (LaunchApp, String) -> Void
    let dropOnFolderApp: (String, String, LaunchDropPlacement) -> Void
    let dropIntoFolder: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(size: geometry.size, itemCount: apps.count, spacingScale: spacingScale, mode: .folder)

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
                            reveal: reveal,
                            beginDrag: {
                                beginDragging(app, folderID)
                            }
                        )
                        .onDrop(
                            of: [.plainText],
                            delegate: FolderAppDropDelegate(
                                folderID: folderID,
                                targetAppID: app.id,
                                tileSize: CGSize(width: metrics.tileWidth, height: metrics.tileHeight),
                                drop: dropOnFolderApp
                            )
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onDrop(
                of: [.plainText],
                delegate: FolderDropDelegate(folderID: folderID, drop: dropIntoFolder)
            )
            .scrollIndicators(.hidden)
        }
    }
}

private struct PageItemDropDelegate: DropDelegate {
    let pageID: String
    let targetItemID: String
    let tileSize: CGSize
    let drop: (String, String, LaunchDropPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drop(targetItemID, pageID, placement(for: info.location, tileSize: tileSize))
        return true
    }
}

private struct PagePositionDropDelegate: DropDelegate {
    let pageID: String
    let index: Int
    let drop: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drop(pageID, index)
        return true
    }
}

private struct FolderAppDropDelegate: DropDelegate {
    let folderID: String
    let targetAppID: String
    let tileSize: CGSize
    let drop: (String, String, LaunchDropPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drop(targetAppID, folderID, placement(for: info.location, tileSize: tileSize))
        return true
    }
}

private struct FolderDropDelegate: DropDelegate {
    let folderID: String
    let drop: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drop(folderID)
        return true
    }
}

private struct FolderBackdropDropDelegate: DropDelegate {
    let drop: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drop()
        return true
    }
}

private func placement(for location: CGPoint, tileSize: CGSize) -> LaunchDropPlacement {
    if location.x < tileSize.width * 0.30 {
        return .before
    }

    if location.x > tileSize.width * 0.70 {
        return .after
    }

    return .combine
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
    var beginDrag: (() -> Void)? = nil

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
        .onDrag {
            beginDrag?()
            return NSItemProvider(object: app.id as NSString)
        }
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
    var beginDrag: (() -> Void)? = nil

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
        .onDrag {
            beginDrag?()
            return NSItemProvider(object: folder.id as NSString)
        }
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
    let itemDragTargets: [PageItemDragTarget]
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (CGFloat, CGFloat) -> Void
    let beginItemDrag: (LaunchItem, String) -> Void
    let dropOnPageItem: (String, String, LaunchDropPlacement) -> Void
    let dropOnPagePosition: (String, Int) -> Void
    let movePrevious: () -> Void
    let moveNext: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = PageInputView(frame: .zero)
        context.coordinator.installMonitor(attachedTo: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.pageWidth = pageWidth
        context.coordinator.canMovePrevious = canMovePrevious
        context.coordinator.canMoveNext = canMoveNext
        context.coordinator.itemDragTargets = itemDragTargets
        context.coordinator.dragChanged = dragChanged
        context.coordinator.dragEnded = dragEnded
        context.coordinator.beginItemDrag = beginItemDrag
        context.coordinator.dropOnPageItem = dropOnPageItem
        context.coordinator.dropOnPagePosition = dropOnPagePosition
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
        var itemDragTargets: [PageItemDragTarget] = []
        var dragChanged: (CGFloat) -> Void = { _ in }
        var dragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        var beginItemDrag: (LaunchItem, String) -> Void = { _, _ in }
        var dropOnPageItem: (String, String, LaunchDropPlacement) -> Void = { _, _, _ in }
        var dropOnPagePosition: (String, Int) -> Void = { _, _ in }
        var movePrevious: () -> Void = {}
        var moveNext: () -> Void = {}

        private weak var view: NSView?
        private var monitor: Any?
        private var selectedPage = 0
        private var accumulatedScrollDeltaX: CGFloat = 0
        private var lastScrollEventDate = Date.distantPast
        private var lastScrollMoveDate = Date.distantPast
        private var didHandleCurrentScrollGesture = false
        private var trackedItemDragTarget: PageItemDragTarget?
        private var isTrackingDrag = false
        private var didBeginItemDrag = false
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

            let now = Date()
            let hasPhase = event.phase != [] || event.momentumPhase != []
            if !hasPhase, now.timeIntervalSince(lastScrollEventDate) > 0.42 {
                resetScrollState()
            }

            lastScrollEventDate = now

            let shouldResetAtEnd = event.phase == .ended
                || event.phase == .cancelled
                || event.momentumPhase == .ended
                || event.momentumPhase == .cancelled

            if event.phase == .began || event.phase == .mayBegin {
                resetScrollState()
                lastScrollEventDate = now
            }

            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            guard abs(horizontal) > max(1.2, abs(vertical) * 1.2) else {
                if shouldResetAtEnd, !didHandleCurrentScrollGesture {
                    accumulatedScrollDeltaX = 0
                }

                return event
            }

            accumulatedScrollDeltaX += horizontal

            if !hasPhase {
                _ = performScrollPageMoveIfNeeded(threshold: scrollThreshold(for: event), cooldown: 0.65)
                return nil
            }

            if shouldResetAtEnd {
                _ = performScrollPageMoveIfNeeded(threshold: scrollThreshold(for: event), cooldown: 0)
                if !didHandleCurrentScrollGesture {
                    accumulatedScrollDeltaX = 0
                }
            }

            return nil
        }

        private func scrollThreshold(for event: NSEvent) -> CGFloat {
            if event.hasPreciseScrollingDeltas {
                return min(max(pageWidth * 0.045, 70), 140)
            }

            return min(max(pageWidth * 0.012, 8), 28)
        }

        private func performScrollPageMoveIfNeeded(threshold: CGFloat, cooldown: TimeInterval) -> Bool {
            guard !didHandleCurrentScrollGesture,
                  abs(accumulatedScrollDeltaX) >= threshold else {
                return false
            }

            let now = Date()
            guard cooldown <= 0 || now.timeIntervalSince(lastScrollMoveDate) > cooldown else {
                return false
            }

            if accumulatedScrollDeltaX > 0 {
                if canMovePrevious {
                    movePrevious()
                    lastScrollMoveDate = now
                    didHandleCurrentScrollGesture = true
                    return true
                }
            } else if canMoveNext {
                moveNext()
                lastScrollMoveDate = now
                didHandleCurrentScrollGesture = true
                return true
            }

            didHandleCurrentScrollGesture = true
            return false
        }

        private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
            guard isEventInsideBridge(event) else {
                cancelDrag()
                return event
            }

            if let target = itemDragTarget(for: event) {
                trackedItemDragTarget = target
                isTrackingDrag = false
                didBeginItemDrag = false
                didBeginPagingDrag = false
                accumulatedDragX = 0
                accumulatedDragY = 0
                dragStartDate = Date()
                return event
            }

            isTrackingDrag = true
            trackedItemDragTarget = nil
            didBeginItemDrag = false
            didBeginPagingDrag = false
            accumulatedDragX = 0
            accumulatedDragY = 0
            dragStartDate = Date()
            return event
        }

        private func handleMouseDragged(_ event: NSEvent) -> NSEvent? {
            if trackedItemDragTarget != nil {
                accumulatedDragX += event.deltaX
                accumulatedDragY += event.deltaY

                if didBeginItemDrag || hypot(accumulatedDragX, accumulatedDragY) > 5 {
                    if !didBeginItemDrag, let target = trackedItemDragTarget {
                        beginItemDrag(target.item, target.pageID)
                    }

                    didBeginItemDrag = true
                    return nil
                }

                return event
            }

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
            if let sourceTarget = trackedItemDragTarget {
                let shouldConsume = didBeginItemDrag

                if didBeginItemDrag {
                    performItemDrop(from: sourceTarget, event: event)
                }

                resetDragState()
                return shouldConsume ? nil : event
            }

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

        private func itemDragTarget(for event: NSEvent) -> PageItemDragTarget? {
            guard let view,
                  let window = view.window,
                  event.window === window else {
                return nil
            }

            let point = view.convert(event.locationInWindow, from: nil)
            return itemDragTargets.first { $0.rect.contains(point) }
        }

        private func performItemDrop(from sourceTarget: PageItemDragTarget, event: NSEvent) {
            guard let view,
                  let window = view.window,
                  event.window === window else {
                return
            }

            let point = view.convert(event.locationInWindow, from: nil)
            if let destination = itemDragTargets.first(where: { $0.rect.contains(point) }),
               destination.item.id != sourceTarget.item.id {
                let localPoint = CGPoint(
                    x: point.x - destination.rect.minX,
                    y: point.y - destination.rect.minY
                )
                dropOnPageItem(
                    destination.item.id,
                    destination.pageID,
                    placement(for: localPoint, tileSize: destination.rect.size)
                )
            } else {
                dropOnPagePosition(sourceTarget.pageID, Int.max)
            }
        }

        private func resetScrollState() {
            accumulatedScrollDeltaX = 0
            didHandleCurrentScrollGesture = false
        }

        private func cancelDrag() {
            if didBeginPagingDrag {
                dragChanged(0)
            }

            resetDragState()
        }

        private func resetDragState() {
            isTrackingDrag = false
            trackedItemDragTarget = nil
            didBeginItemDrag = false
            didBeginPagingDrag = false
            accumulatedDragX = 0
            accumulatedDragY = 0
            dragStartDate = .distantPast
        }
    }
}

private final class PageInputView: NSView {
    override var isFlipped: Bool {
        true
    }
}
