import Foundation

final class LaunchSnapshotCache {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> LaunchSnapshot? {
        load(from: cacheURL(fileName: "launch-cache.json"))
    }

    func loadUserLayout() -> LaunchSnapshot? {
        load(from: cacheURL(fileName: "launch-layout.json"))
    }

    func saveUserLayout(_ snapshot: LaunchSnapshot) {
        save(snapshot, to: cacheURL(fileName: "launch-layout.json"))
    }

    func save(_ snapshot: LaunchSnapshot) {
        save(snapshot, to: cacheURL(fileName: "launch-cache.json"))
    }

    private func load(from url: URL) -> LaunchSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedSnapshot.self, from: data) else {
            return nil
        }

        let pages = cached.pages.map { page in
            LaunchPage(
                id: page.id,
                title: page.title,
                items: page.items.compactMap(LaunchItem.init(cachedItem:))
            )
        }

        guard !pages.isEmpty else {
            return nil
        }

        return LaunchSnapshot(
            pages: pages,
            totalAppCount: cached.totalAppCount,
            importedAppCount: cached.importedAppCount,
            launchpadDatabasePath: cached.launchpadDatabasePath,
            usedLaunchpadLayout: cached.usedLaunchpadLayout,
            generatedAt: cached.generatedAt
        )
    }

    private func save(_ snapshot: LaunchSnapshot, to url: URL) {
        let cached = CachedSnapshot(snapshot: snapshot)

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(cached)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Cache writes are best effort; startup must not depend on them.
        }
    }

    private func cacheURL(fileName: String) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return baseURL
            .appendingPathComponent("LaunchOS", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

private struct CachedSnapshot: Codable {
    let pages: [CachedPage]
    let totalAppCount: Int
    let importedAppCount: Int
    let launchpadDatabasePath: String?
    let usedLaunchpadLayout: Bool
    let generatedAt: Date

    init(snapshot: LaunchSnapshot) {
        self.pages = snapshot.pages.map(CachedPage.init(page:))
        self.totalAppCount = snapshot.totalAppCount
        self.importedAppCount = snapshot.importedAppCount
        self.launchpadDatabasePath = snapshot.launchpadDatabasePath
        self.usedLaunchpadLayout = snapshot.usedLaunchpadLayout
        self.generatedAt = snapshot.generatedAt
    }
}

private struct CachedPage: Codable {
    let id: String
    let title: String
    let items: [CachedItem]

    init(page: LaunchPage) {
        self.id = page.id
        self.title = page.title
        self.items = page.items.map(CachedItem.init(item:))
    }
}

private enum CachedItem: Codable {
    case app(CachedApp)
    case folder(CachedFolder)

    private enum CodingKeys: String, CodingKey {
        case type
        case app
        case folder
    }

    init(item: LaunchItem) {
        switch item {
        case .app(let app):
            self = .app(CachedApp(app: app))
        case .folder(let folder):
            self = .folder(CachedFolder(folder: folder))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "app":
            self = .app(try container.decode(CachedApp.self, forKey: .app))
        case "folder":
            self = .folder(try container.decode(CachedFolder.self, forKey: .folder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown cached item type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .app(let app):
            try container.encode("app", forKey: .type)
            try container.encode(app, forKey: .app)
        case .folder(let folder):
            try container.encode("folder", forKey: .type)
            try container.encode(folder, forKey: .folder)
        }
    }
}

private struct CachedFolder: Codable {
    let id: String
    let title: String
    let apps: [CachedApp]

    init(folder: LaunchFolder) {
        self.id = folder.id
        self.title = folder.title
        self.apps = folder.apps.map(CachedApp.init(app:))
    }
}

private struct CachedApp: Codable {
    let id: String
    let title: String
    let bundleIdentifier: String?
    let url: URL
    let source: ApplicationSource

    init(app: LaunchApp) {
        self.id = app.id
        self.title = app.title
        self.bundleIdentifier = app.bundleIdentifier
        self.url = app.url
        self.source = app.source
    }
}

private extension LaunchItem {
    init?(cachedItem: CachedItem) {
        switch cachedItem {
        case .app(let app):
            self = .app(LaunchApp(cachedApp: app))
        case .folder(let folder):
            let apps = folder.apps.map(LaunchApp.init(cachedApp:))
            self = .folder(LaunchFolder(id: folder.id, title: folder.title, apps: apps))
        }
    }
}

private extension LaunchApp {
    init(cachedApp: CachedApp) {
        self.init(
            id: cachedApp.id,
            title: cachedApp.title,
            bundleIdentifier: cachedApp.bundleIdentifier,
            url: cachedApp.url,
            source: cachedApp.source
        )
    }
}
