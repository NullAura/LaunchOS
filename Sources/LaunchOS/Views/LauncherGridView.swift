import SwiftUI

struct PagedLauncherView: View {
    let pages: [LaunchPage]
    @Binding var selectedPage: Int
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void
    let openFolder: (LaunchFolder) -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let pageIndex = min(max(selectedPage, 0), max(pages.count - 1, 0))

        GeometryReader { geometry in
            ZStack {
                LaunchItemGrid(
                    items: pages[pageIndex].items,
                    geometry: geometry,
                    launchingAppID: launchingAppID,
                    launch: launch,
                    reveal: reveal,
                    openFolder: openFolder
                )
                .offset(x: dragOffset)
                .animation(.snappy(duration: 0.22), value: selectedPage)

                PageStepButton(systemName: "chevron.left") {
                    selectedPage = max(selectedPage - 1, 0)
                }
                .disabled(selectedPage == 0)
                .opacity(selectedPage == 0 ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)

                PageStepButton(systemName: "chevron.right") {
                    selectedPage = min(selectedPage + 1, pages.count - 1)
                }
                .disabled(selectedPage >= pages.count - 1)
                .opacity(selectedPage >= pages.count - 1 ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 22)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 35)
                    .onChanged { value in
                        dragOffset = value.translation.width * 0.18
                    }
                    .onEnded { value in
                        if value.translation.width < -90 {
                            selectedPage = min(selectedPage + 1, pages.count - 1)
                        } else if value.translation.width > 90 {
                            selectedPage = max(selectedPage - 1, 0)
                        }

                        dragOffset = 0
                    }
            )
        }
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
            let width = min(680, max(460, geometry.size.width - 100))
            let height = min(520, max(360, geometry.size.height - 140))

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
                        launchingAppID: launchingAppID,
                        launch: launch,
                        reveal: reveal
                    )
                }
                .frame(width: width, height: height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(radius: 28)
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

        ScrollView {
            LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                ForEach(items) { item in
                    switch item {
                    case .app(let app):
                        AppTile(
                            app: app,
                            tileWidth: metrics.tileWidth,
                            tileHeight: metrics.tileHeight,
                            iconSize: metrics.iconSize,
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
                            open: openFolder
                        )
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LaunchAppGrid: View {
    let apps: [LaunchApp]
    let spacingScale: CGFloat
    let launchingAppID: String?
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(size: geometry.size, itemCount: apps.count, spacingScale: spacingScale)

            ScrollView {
                LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                    ForEach(apps) { app in
                        AppTile(
                            app: app,
                            tileWidth: metrics.tileWidth,
                            tileHeight: metrics.tileHeight,
                            iconSize: metrics.iconSize,
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
    let isLaunching: Bool
    let launch: (LaunchApp) -> Void
    let reveal: (LaunchApp) -> Void

    var body: some View {
        Button {
            launch(app)
        } label: {
            VStack(spacing: 8) {
                Image(nsImage: IconProvider.shared.icon(for: app))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)

                Text(app.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: tileWidth, height: 34, alignment: .top)
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
    let open: (LaunchFolder) -> Void

    var body: some View {
        Button {
            open(folder)
        } label: {
            VStack(spacing: 8) {
                FolderPreview(apps: Array(folder.apps.prefix(9)), iconSize: iconSize)
                    .frame(width: iconSize, height: iconSize)

                Text(folder.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: tileWidth, height: 34, alignment: .top)
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
        let miniIconSize = max(15, (iconSize - 24) / 3)
        let spacing = max(3, iconSize * 0.045)

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
            .padding(iconSize * 0.12)
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
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat

    init(size: CGSize, itemCount: Int, spacingScale: CGFloat = 1) {
        let baseTileWidth: CGFloat = 112
        let baseIconSize: CGFloat = 76
        let baseColumnSpacing: CGFloat = 34
        let baseRowSpacing: CGFloat = 31
        let baseTileLabelHeight: CGFloat = 48

        let maxColumns: Int
        if size.width >= 3300 {
            maxColumns = 10
        } else if size.width >= 2500 {
            maxColumns = 9
        } else {
            maxColumns = 7
        }

        let columnCount = max(3, min(maxColumns, max(itemCount, 1)))
        let rowCount = max(1, ceil(CGFloat(max(itemCount, 1)) / CGFloat(columnCount)))

        let targetWidthFraction: CGFloat
        if size.width >= 3300 {
            targetWidthFraction = 0.74
        } else if size.width >= 2500 {
            targetWidthFraction = 0.70
        } else {
            targetWidthFraction = 0.69
        }

        let targetHeightFraction: CGFloat = size.height >= 1400 ? 0.72 : 0.68
        let baseGridWidth = CGFloat(columnCount) * baseTileWidth + CGFloat(max(columnCount - 1, 0)) * baseColumnSpacing
        let baseGridHeight = rowCount * (baseIconSize + baseTileLabelHeight) + CGFloat(max(Int(rowCount) - 1, 0)) * baseRowSpacing
        let widthScale = (size.width * targetWidthFraction) / baseGridWidth
        let heightScale = (size.height * targetHeightFraction) / baseGridHeight
        let screenScale = min(max(min(widthScale, heightScale), 0.9), 2.35)

        let columnSpacing = baseColumnSpacing * screenScale * spacingScale
        self.tileWidth = baseTileWidth * screenScale
        self.iconSize = baseIconSize * screenScale
        self.tileHeight = iconSize + baseTileLabelHeight
        self.rowSpacing = baseRowSpacing * screenScale * spacingScale
        self.horizontalPadding = max(34, (size.width - (tileWidth * CGFloat(columnCount)) - (columnSpacing * CGFloat(columnCount - 1))) / 2)
        self.columns = Array(repeating: GridItem(.fixed(tileWidth), spacing: columnSpacing), count: columnCount)
    }
}
