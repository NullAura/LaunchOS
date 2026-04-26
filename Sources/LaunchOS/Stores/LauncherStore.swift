import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var pages: [LaunchPage] = []
    @Published private(set) var isLoading = true
    @Published private(set) var statusText = "正在准备应用列表"
    @Published private(set) var launchingAppID: String?
    @Published private(set) var isClosing = false
    @Published var searchText = ""
    @Published var activeFolder: LaunchFolder?

    private let library: LaunchLibrary
    private var hasLoaded = false
    private var isUsingUserLayout = false
    private var launchpadDatabasePath: String?
    private var draggedSource: DragSource?

    init(library: LaunchLibrary = LaunchLibrary()) {
        self.library = library

        if let userLayout = library.loadUserLayoutSnapshot() {
            isUsingUserLayout = true
            apply(userLayout, isRefreshing: false)
        } else if let launchpadSnapshot = library.loadLaunchpadSnapshot() {
            apply(launchpadSnapshot, isRefreshing: false)
            library.saveSnapshotToCache(launchpadSnapshot)
        } else if let cachedSnapshot = library.loadCachedSnapshot() {
            apply(cachedSnapshot, isRefreshing: false)
        }
    }

    var searchResults: [LaunchApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        let normalizedQuery = query.lowercased()
        return allApps()
            .filter { app in
                app.title.lowercased().contains(normalizedQuery)
                    || (app.bundleIdentifier?.lowercased().contains(normalizedQuery) ?? false)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true

        if isUsingUserLayout {
            return
        }

        if !pages.isEmpty {
            refreshInBackground()
            return
        }

        loadFastThenRefresh(cachedSnapshot: library.loadCachedSnapshot())
    }

    func reload() {
        hasLoaded = true
        isLoading = pages.isEmpty
        statusText = "正在同步旧启动台布局"
        refreshInBackground()
    }

    private func loadFastThenRefresh(cachedSnapshot: LaunchSnapshot? = nil) {
        isLoading = pages.isEmpty
        statusText = "正在载入启动台布局"

        Task {
            let fastSnapshot = await Task.detached(priority: .userInitiated) {
                let library = LaunchLibrary()
                return library.loadLaunchpadSnapshot()
            }.value

            if let fastSnapshot {
                apply(fastSnapshot, isRefreshing: false)
                refreshInBackground()
            } else if let cachedSnapshot {
                apply(cachedSnapshot, isRefreshing: false)
                refreshInBackground()
            } else {
                refreshInBackground()
            }
        }
    }

    private func refreshInBackground() {
        guard !isUsingUserLayout else {
            return
        }

        Task {
            let snapshot = await Task.detached(priority: .utility) {
                let library = LaunchLibrary()
                let snapshot = library.loadSnapshot()
                library.saveSnapshotToCache(snapshot)
                return snapshot
            }.value

            apply(snapshot, isRefreshing: false)
        }
    }

    private func apply(_ snapshot: LaunchSnapshot, isRefreshing: Bool) {
        pages = snapshot.pages
        isLoading = isRefreshing
        statusText = Self.statusText(for: snapshot)
        launchpadDatabasePath = snapshot.launchpadDatabasePath
    }

    func beginDragging(item: LaunchItem, fromPageID pageID: String) {
        draggedSource = .pageItem(pageID: pageID, itemID: item.id)
    }

    func beginDragging(app: LaunchApp, fromFolderID folderID: String) {
        draggedSource = .folderApp(folderID: folderID, appID: app.id)
    }

    func clearDragging() {
        draggedSource = nil
    }

    func dropDraggedItem(onPageItem targetItemID: String, inPageID pageID: String, placement: LaunchDropPlacement) {
        guard draggedSource?.itemID != targetItemID else {
            clearDragging()
            return
        }

        switch placement {
        case .combine:
            combineDraggedItem(withPageItem: targetItemID, inPageID: pageID)
        case .before:
            moveDraggedItem(toPageID: pageID, beforeItemID: targetItemID)
        case .after:
            moveDraggedItem(toPageID: pageID, afterItemID: targetItemID)
        }
    }

    func dropDraggedItem(inPageID pageID: String, at index: Int) {
        guard let content = removeDraggedContent() else {
            clearDragging()
            return
        }

        insert(content, inPageID: pageID, at: index)
        finishLayoutEdit()
    }

    func dropDraggedItemIntoFolder(_ folderID: String) {
        guard case .app(let app) = removeDraggedContent() else {
            clearDragging()
            return
        }

        append(app, toFolderID: folderID)
        finishLayoutEdit()
    }

    func dropDraggedFolderApp(on targetAppID: String, inFolderID folderID: String, placement: LaunchDropPlacement) {
        guard draggedSource?.folderAppID != targetAppID,
              case .app(let app) = removeDraggedContent() else {
            clearDragging()
            return
        }

        insert(app, inFolderID: folderID, relativeToAppID: targetAppID, placement: placement)
        finishLayoutEdit()
    }

    func dropDraggedItemOutOfFolder(toPageID pageID: String) {
        guard let content = removeDraggedContent() else {
            clearDragging()
            return
        }

        insert(content, inPageID: pageID, at: Int.max)

        withAnimation(.smooth(duration: 0.2)) {
            activeFolder = nil
        }

        finishLayoutEdit()
    }

    func launch(_ app: LaunchApp) {
        guard !isClosing else {
            return
        }

        launchingAppID = app.id

        Task {
            try? await Task.sleep(for: .milliseconds(180))

            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                isClosing = true
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        withAnimation(.smooth(duration: 0.16)) {
                            self?.launchingAppID = nil
                            self?.isClosing = false
                        }
                        self?.statusText = "无法打开 \(app.title): \(error.localizedDescription)"
                    } else {
                        self?.statusText = "已打开 \(app.title)"
                        self?.closeLauncherSoon()
                    }
                }
            }
        }
    }

    func revealInFinder(_ app: LaunchApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func openFolder(_ folder: LaunchFolder) {
        withAnimation(.smooth(duration: 0.28)) {
            activeFolder = folder
        }
    }

    func closeFolder() {
        withAnimation(.smooth(duration: 0.24)) {
            activeFolder = nil
        }
    }

    func handleExitCommand() {
        if activeFolder != nil {
            activeFolder = nil
        } else {
            closeLauncher()
        }
    }

    func closeLauncher() {
        guard !isClosing else {
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            isClosing = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(220))
            NSApp.terminate(nil)
        }
    }

    private func moveDraggedItem(toPageID pageID: String, beforeItemID targetItemID: String) {
        guard let content = removeDraggedContent(),
              let targetIndex = itemIndex(itemID: targetItemID, inPageID: pageID) else {
            clearDragging()
            return
        }

        insert(content, inPageID: pageID, at: targetIndex)
        finishLayoutEdit()
    }

    private func moveDraggedItem(toPageID pageID: String, afterItemID targetItemID: String) {
        guard let content = removeDraggedContent(),
              let targetIndex = itemIndex(itemID: targetItemID, inPageID: pageID) else {
            clearDragging()
            return
        }

        insert(content, inPageID: pageID, at: targetIndex + 1)
        finishLayoutEdit()
    }

    private func combineDraggedItem(withPageItem targetItemID: String, inPageID pageID: String) {
        guard case .app(let draggedApp) = removeDraggedContent(),
              let targetLocation = pageItemLocation(itemID: targetItemID, inPageID: pageID) else {
            clearDragging()
            return
        }

        var page = pages[targetLocation.pageIndex]
        var items = page.items
        let target = items[targetLocation.itemIndex]

        switch target {
        case .app(let targetApp):
            guard targetApp.id != draggedApp.id else {
                clearDragging()
                return
            }

            let folder = LaunchFolder(
                id: "custom-\(UUID().uuidString)",
                title: "文件夹",
                apps: [targetApp, draggedApp]
            )
            items[targetLocation.itemIndex] = .folder(folder)
            page = LaunchPage(id: page.id, title: page.title, items: items)
            pages[targetLocation.pageIndex] = page
            finishLayoutEdit()

        case .folder(let folder):
            append(draggedApp, toFolderID: folder.id)
            finishLayoutEdit()
        }
    }

    private func removeDraggedContent() -> LaunchItem? {
        guard let draggedSource else {
            return nil
        }

        switch draggedSource {
        case .pageItem(let pageID, let itemID):
            guard let pageIndex = pages.firstIndex(where: { $0.id == pageID }),
                  let itemIndex = pages[pageIndex].items.firstIndex(where: { $0.id == itemID }) else {
                return nil
            }

            var page = pages[pageIndex]
            var items = page.items
            let item = items.remove(at: itemIndex)
            page = LaunchPage(id: page.id, title: page.title, items: items)
            pages[pageIndex] = page
            return item

        case .folderApp(let folderID, let appID):
            guard let folderLocation = folderLocation(folderID),
                  let appIndex = folderLocation.folder.apps.firstIndex(where: { $0.id == appID }) else {
                return nil
            }

            var apps = folderLocation.folder.apps
            let app = apps.remove(at: appIndex)
            replaceFolder(at: folderLocation, withApps: apps)
            return .app(app)
        }
    }

    private func insert(_ item: LaunchItem, inPageID pageID: String, at index: Int) {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageID }) else {
            return
        }

        let page = pages[pageIndex]
        var items = page.items
        let insertionIndex = min(max(index, 0), items.count)
        items.insert(item, at: insertionIndex)
        pages[pageIndex] = LaunchPage(id: page.id, title: page.title, items: items)
        normalizePages()
    }

    private func append(_ app: LaunchApp, toFolderID folderID: String) {
        guard let location = folderLocation(folderID),
              !location.folder.apps.contains(where: { $0.id == app.id }) else {
            return
        }

        replaceFolder(at: location, withApps: location.folder.apps + [app])
    }

    private func insert(
        _ app: LaunchApp,
        inFolderID folderID: String,
        relativeToAppID targetAppID: String,
        placement: LaunchDropPlacement
    ) {
        guard let location = folderLocation(folderID),
              let targetIndex = location.folder.apps.firstIndex(where: { $0.id == targetAppID }),
              !location.folder.apps.contains(where: { $0.id == app.id }) else {
            return
        }

        var apps = location.folder.apps
        let insertionIndex: Int
        switch placement {
        case .before:
            insertionIndex = targetIndex
        case .after, .combine:
            insertionIndex = targetIndex + 1
        }

        apps.insert(app, at: min(insertionIndex, apps.count))
        replaceFolder(at: location, withApps: apps)
    }

    private func replaceFolder(at location: FolderLocation, withApps apps: [LaunchApp]) {
        var page = pages[location.pageIndex]
        var items = page.items

        if apps.isEmpty {
            items.remove(at: location.itemIndex)
        } else if apps.count == 1 {
            items[location.itemIndex] = .app(apps[0])
        } else {
            items[location.itemIndex] = .folder(
                LaunchFolder(
                    id: location.folder.id,
                    title: location.folder.title,
                    apps: apps
                )
            )
        }

        page = LaunchPage(id: page.id, title: page.title, items: items)
        pages[location.pageIndex] = page
        syncActiveFolder(location.folder.id)
    }

    private func itemIndex(itemID: String, inPageID pageID: String) -> Int? {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageID }) else {
            return nil
        }

        return pages[pageIndex].items.firstIndex(where: { $0.id == itemID })
    }

    private func pageItemLocation(itemID: String, inPageID pageID: String) -> (pageIndex: Int, itemIndex: Int)? {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageID }),
              let itemIndex = pages[pageIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        return (pageIndex, itemIndex)
    }

    private func folderLocation(_ folderID: String) -> FolderLocation? {
        for pageIndex in pages.indices {
            for itemIndex in pages[pageIndex].items.indices {
                if case .folder(let folder) = pages[pageIndex].items[itemIndex],
                   folder.id == folderID {
                    return FolderLocation(pageIndex: pageIndex, itemIndex: itemIndex, folder: folder)
                }
            }
        }

        return nil
    }

    private func syncActiveFolder(_ folderID: String) {
        guard activeFolder?.id == folderID else {
            return
        }

        activeFolder = folderLocation(folderID)?.folder
    }

    private func normalizePages() {
        let pageSize = 35
        var normalizedPages = pages
        var index = 0

        while index < normalizedPages.count {
            let page = normalizedPages[index]
            if page.items.count > pageSize {
                let visibleItems = Array(page.items.prefix(pageSize))
                let overflowItems = Array(page.items.dropFirst(pageSize))
                normalizedPages[index] = LaunchPage(id: page.id, title: page.title, items: visibleItems)

                if normalizedPages.indices.contains(index + 1) {
                    let nextPage = normalizedPages[index + 1]
                    normalizedPages[index + 1] = LaunchPage(
                        id: nextPage.id,
                        title: nextPage.title,
                        items: overflowItems + nextPage.items
                    )
                } else {
                    let pageNumber = normalizedPages.count + 1
                    normalizedPages.append(
                        LaunchPage(
                            id: "custom-page-\(UUID().uuidString)",
                            title: "第 \(pageNumber) 页",
                            items: overflowItems
                        )
                    )
                }
            }

            index += 1
        }

        pages = normalizedPages
    }

    private func finishLayoutEdit() {
        clearDragging()
        isUsingUserLayout = true
        let snapshot = currentSnapshot()
        library.saveUserLayoutSnapshot(snapshot)
        library.saveSnapshotToCache(snapshot)
    }

    private func currentSnapshot() -> LaunchSnapshot {
        let appCount = allApps().count
        return LaunchSnapshot(
            pages: pages,
            totalAppCount: appCount,
            importedAppCount: appCount,
            launchpadDatabasePath: launchpadDatabasePath,
            usedLaunchpadLayout: true,
            generatedAt: Date()
        )
    }

    private func allApps() -> [LaunchApp] {
        var seen: Set<String> = []
        var apps: [LaunchApp] = []

        for page in pages {
            for item in page.items {
                switch item {
                case .app(let app):
                    guard seen.insert(app.id).inserted else {
                        continue
                    }
                    apps.append(app)
                case .folder(let folder):
                    for app in folder.apps where seen.insert(app.id).inserted {
                        apps.append(app)
                    }
                }
            }
        }

        return apps
    }

    private static func statusText(for snapshot: LaunchSnapshot) -> String {
        if snapshot.usedLaunchpadLayout {
            return "已导入旧启动台布局：\(snapshot.importedAppCount) 个项目，当前共 \(snapshot.totalAppCount) 个应用"
        }

        return "未找到旧启动台布局，已扫描 \(snapshot.totalAppCount) 个应用"
    }

    private func closeLauncherSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            NSApp.terminate(nil)
        }
    }
}

private enum DragSource {
    case pageItem(pageID: String, itemID: String)
    case folderApp(folderID: String, appID: String)

    var itemID: String? {
        guard case .pageItem(_, let itemID) = self else {
            return nil
        }

        return itemID
    }

    var folderAppID: String? {
        guard case .folderApp(_, let appID) = self else {
            return nil
        }

        return appID
    }
}

private struct FolderLocation {
    let pageIndex: Int
    let itemIndex: Int
    let folder: LaunchFolder
}
