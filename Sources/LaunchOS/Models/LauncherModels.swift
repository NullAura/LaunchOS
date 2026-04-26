import Foundation

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let title: String
    let bundleIdentifier: String?
    let url: URL
    let source: ApplicationSource

    var id: String {
        if let bundleIdentifier {
            return bundleIdentifier.lowercased()
        }

        return url.path(percentEncoded: false).lowercased()
    }
}

enum ApplicationSource: String, Codable, Sendable {
    case applications = "Applications"
    case systemApplications = "System"
    case userApplications = "User"
    case workspace = "Workspace"
}

struct LaunchApp: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let bundleIdentifier: String?
    let url: URL
    let source: ApplicationSource

    init(id: String, title: String, bundleIdentifier: String?, url: URL, source: ApplicationSource) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.source = source
    }

    init(installedApplication: InstalledApplication, preferredTitle: String? = nil) {
        self.id = installedApplication.id
        self.title = preferredTitle?.nilIfBlank ?? installedApplication.title
        self.bundleIdentifier = installedApplication.bundleIdentifier
        self.url = installedApplication.url
        self.source = installedApplication.source
    }
}

struct LaunchFolder: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let apps: [LaunchApp]
}

enum LaunchItem: Identifiable, Hashable, Sendable {
    case app(LaunchApp)
    case folder(LaunchFolder)

    var id: String {
        switch self {
        case .app(let app):
            return "app-\(app.id)"
        case .folder(let folder):
            return "folder-\(folder.id)"
        }
    }
}

struct LaunchPage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [LaunchItem]
}

struct LaunchSnapshot: Sendable {
    let pages: [LaunchPage]
    let totalAppCount: Int
    let importedAppCount: Int
    let launchpadDatabasePath: String?
    let usedLaunchpadLayout: Bool
    let generatedAt: Date
}

struct ImportedLaunchpadLayout: Sendable {
    let databasePath: String
    let pages: [ImportedLaunchpadPage]
}

struct ImportedLaunchpadPage: Identifiable, Sendable {
    let id: Int
    let order: Int
    let items: [ImportedLaunchpadItem]
}

enum ImportedLaunchpadItem: Sendable {
    case app(ImportedLaunchpadApp)
    case folder(ImportedLaunchpadFolder)
}

struct ImportedLaunchpadApp: Identifiable, Sendable {
    let id: Int
    let title: String
    let bundleIdentifier: String
    let url: URL?
}

struct ImportedLaunchpadFolder: Identifiable, Sendable {
    let id: Int
    let title: String
    let apps: [ImportedLaunchpadApp]
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
