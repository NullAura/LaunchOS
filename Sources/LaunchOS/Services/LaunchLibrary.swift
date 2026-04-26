import Foundation

final class LaunchLibrary {
    private let scanner: ApplicationScanner
    private let importer: LaunchpadLayoutImporter
    private let cache: LaunchSnapshotCache

    init(
        scanner: ApplicationScanner = ApplicationScanner(),
        importer: LaunchpadLayoutImporter = LaunchpadLayoutImporter(),
        cache: LaunchSnapshotCache = LaunchSnapshotCache()
    ) {
        self.scanner = scanner
        self.importer = importer
        self.cache = cache
    }

    func loadCachedSnapshot() -> LaunchSnapshot? {
        cache.load()
    }

    func loadUserLayoutSnapshot() -> LaunchSnapshot? {
        cache.loadUserLayout()
    }

    func saveSnapshotToCache(_ snapshot: LaunchSnapshot) {
        cache.save(snapshot)
    }

    func saveUserLayoutSnapshot(_ snapshot: LaunchSnapshot) {
        cache.saveUserLayout(snapshot)
    }

    func loadLaunchpadSnapshot() -> LaunchSnapshot? {
        guard let layout = try? importer.importLayoutIfAvailable() else {
            return nil
        }

        let materialized = materializeFast(layout: layout)
        guard !materialized.pages.isEmpty else {
            return nil
        }

        return LaunchSnapshot(
            pages: materialized.pages,
            totalAppCount: materialized.importedAppCount,
            importedAppCount: materialized.importedAppCount,
            launchpadDatabasePath: layout.databasePath,
            usedLaunchpadLayout: true,
            generatedAt: Date()
        )
    }

    func loadSnapshot() -> LaunchSnapshot {
        let installedApplications = scanner.scanApplications()
        let installedIndex = InstalledApplicationIndex(applications: installedApplications)

        if let layout = try? importer.importLayoutIfAvailable() {
            let materialized = materialize(layout: layout, installedIndex: installedIndex)
            if !materialized.pages.isEmpty {
                return LaunchSnapshot(
                    pages: materialized.pages,
                    totalAppCount: materialized.importedAppCount,
                    importedAppCount: materialized.importedAppCount,
                    launchpadDatabasePath: layout.databasePath,
                    usedLaunchpadLayout: true,
                    generatedAt: Date()
                )
            }
        }

        let fallbackItems = installedApplications.map { LaunchItem.app(LaunchApp(installedApplication: $0)) }
        return LaunchSnapshot(
            pages: pagedItems(fallbackItems, titlePrefix: "应用", idPrefix: "fallback"),
            totalAppCount: installedApplications.count,
            importedAppCount: 0,
            launchpadDatabasePath: nil,
            usedLaunchpadLayout: false,
            generatedAt: Date()
        )
    }

    private func materialize(
        layout: ImportedLaunchpadLayout,
        installedIndex: InstalledApplicationIndex
    ) -> (pages: [LaunchPage], usedApplicationIDs: Set<String>, importedAppCount: Int) {
        var usedApplicationIDs: Set<String> = []
        var importedAppCount = 0

        let importedPages = layout.pages.compactMap { importedPage -> LaunchPage? in
            let items = importedPage.items.compactMap { item -> LaunchItem? in
                switch item {
                case .app(let importedApp):
                    guard let launchApp = launchApp(
                        importedApp: importedApp,
                        installedIndex: installedIndex
                    ) else {
                        return nil
                    }

                    usedApplicationIDs.insert(launchApp.id)
                    importedAppCount += 1
                    return .app(launchApp)

                case .folder(let importedFolder):
                    let apps = importedFolder.apps.compactMap { importedApp -> LaunchApp? in
                        guard let launchApp = launchApp(
                            importedApp: importedApp,
                            installedIndex: installedIndex
                        ) else {
                            return nil
                        }

                        usedApplicationIDs.insert(launchApp.id)
                        importedAppCount += 1
                        return launchApp
                    }

                    guard !apps.isEmpty else {
                        return nil
                    }

                    return .folder(
                        LaunchFolder(
                            id: "launchpad-\(importedFolder.id)",
                            title: importedFolder.title,
                            apps: apps
                        )
                    )
                }
            }

            guard !items.isEmpty else {
                return nil
            }

            return LaunchPage(
                id: "launchpad-page-\(importedPage.id)",
                title: "",
                items: items
            )
        }

        let pages = importedPages.enumerated().map { index, page in
            LaunchPage(
                id: page.id,
                title: "第 \(index + 1) 页",
                items: page.items
            )
        }

        return (pages, usedApplicationIDs, importedAppCount)
    }

    private func materializeFast(
        layout: ImportedLaunchpadLayout
    ) -> (pages: [LaunchPage], importedAppCount: Int) {
        var importedAppCount = 0

        let importedPages = layout.pages.compactMap { importedPage -> LaunchPage? in
            let items = importedPage.items.compactMap { item -> LaunchItem? in
                switch item {
                case .app(let importedApp):
                    guard let launchApp = launchApp(importedApp: importedApp) else {
                        return nil
                    }

                    importedAppCount += 1
                    return .app(launchApp)

                case .folder(let importedFolder):
                    let apps = importedFolder.apps.compactMap { importedApp -> LaunchApp? in
                        guard let launchApp = launchApp(importedApp: importedApp) else {
                            return nil
                        }

                        importedAppCount += 1
                        return launchApp
                    }

                    guard !apps.isEmpty else {
                        return nil
                    }

                    return .folder(
                        LaunchFolder(
                            id: "launchpad-\(importedFolder.id)",
                            title: importedFolder.title,
                            apps: apps
                        )
                    )
                }
            }

            guard !items.isEmpty else {
                return nil
            }

            return LaunchPage(
                id: "launchpad-page-\(importedPage.id)",
                title: "",
                items: items
            )
        }

        let pages = importedPages.enumerated().map { index, page in
            LaunchPage(
                id: page.id,
                title: "第 \(index + 1) 页",
                items: page.items
            )
        }

        return (pages, importedAppCount)
    }

    private func launchApp(
        importedApp: ImportedLaunchpadApp,
        installedIndex: InstalledApplicationIndex
    ) -> LaunchApp? {
        let installed = installedIndex.application(bundleIdentifier: importedApp.bundleIdentifier)
            ?? installedIndex.application(title: importedApp.title)
            ?? scanner.resolve(bundleIdentifier: importedApp.bundleIdentifier, title: importedApp.title)

        if let installed {
            return LaunchApp(installedApplication: installed, preferredTitle: importedApp.title)
        }

        return launchAppFromBookmark(importedApp)
    }

    private func launchApp(importedApp: ImportedLaunchpadApp) -> LaunchApp? {
        if let app = launchAppFromBookmark(importedApp) {
            return app
        }

        guard let installed = scanner.resolve(
            bundleIdentifier: importedApp.bundleIdentifier,
            title: importedApp.title
        ) else {
            return nil
        }

        return LaunchApp(installedApplication: installed, preferredTitle: importedApp.title)
    }

    private func launchAppFromBookmark(_ importedApp: ImportedLaunchpadApp) -> LaunchApp? {
        guard let url = importedApp.url else {
            return nil
        }

        return LaunchApp(
            id: importedApp.bundleIdentifier.lowercased(),
            title: importedApp.title.nilIfBlank ?? importedApp.bundleIdentifier,
            bundleIdentifier: importedApp.bundleIdentifier,
            url: url,
            source: .workspace
        )
    }

    private func pagedItems(_ items: [LaunchItem], titlePrefix: String, idPrefix: String) -> [LaunchPage] {
        let pageSize = 35
        guard !items.isEmpty else {
            return []
        }

        return stride(from: 0, to: items.count, by: pageSize).map { offset in
            let pageNumber = offset / pageSize + 1
            let slice = Array(items[offset..<min(offset + pageSize, items.count)])
            return LaunchPage(
                id: "\(idPrefix)-\(pageNumber)",
                title: "\(titlePrefix) \(pageNumber)",
                items: slice
            )
        }
    }
}

private struct InstalledApplicationIndex {
    private let byBundleIdentifier: [String: InstalledApplication]
    private let byTitle: [String: InstalledApplication]

    init(applications: [InstalledApplication]) {
        var bundleIndex: [String: InstalledApplication] = [:]
        var titleIndex: [String: InstalledApplication] = [:]

        for application in applications {
            if let bundleIdentifier = application.bundleIdentifier?.lowercased() {
                bundleIndex[bundleIdentifier] = application
            }

            titleIndex[application.title.lowercased()] = application
        }

        self.byBundleIdentifier = bundleIndex
        self.byTitle = titleIndex
    }

    func application(bundleIdentifier: String) -> InstalledApplication? {
        byBundleIdentifier[bundleIdentifier.lowercased()]
    }

    func application(title: String) -> InstalledApplication? {
        byTitle[title.lowercased()]
    }
}
