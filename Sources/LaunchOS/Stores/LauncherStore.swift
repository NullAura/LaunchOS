import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var pages: [LaunchPage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusText = "正在准备应用列表"
    @Published private(set) var launchingAppID: String?
    @Published private(set) var isClosing = false
    @Published var searchText = ""
    @Published var activeFolder: LaunchFolder?

    private let library: LaunchLibrary
    private var hasLoaded = false

    init(library: LaunchLibrary = LaunchLibrary()) {
        self.library = library
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

        reload()
    }

    func reload() {
        hasLoaded = true
        isLoading = true
        statusText = "正在扫描应用和旧启动台布局"

        Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                LaunchLibrary().loadSnapshot()
            }.value

            pages = snapshot.pages
            isLoading = false
            statusText = Self.statusText(for: snapshot)
        }
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
