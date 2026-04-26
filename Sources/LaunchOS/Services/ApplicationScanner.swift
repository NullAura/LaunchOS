import AppKit
import Foundation

final class ApplicationScanner {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(fileManager: FileManager = .default, workspace: NSWorkspace = .shared) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func scanApplications() -> [InstalledApplication] {
        var applicationsByID: [String: InstalledApplication] = [:]

        for root in scanRoots() where fileManager.fileExists(atPath: root.url.path) {
            let applications = applications(in: root.url, source: root.source)
            for application in applications {
                applicationsByID[application.id] = preferred(application, over: applicationsByID[application.id])
            }
        }

        return applicationsByID.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func resolve(bundleIdentifier: String, title: String? = nil) -> InstalledApplication? {
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return installedApplication(at: url, source: .workspace, preferredTitle: title)
        }

        return nil
    }

    private func scanRoots() -> [(url: URL, source: ApplicationSource)] {
        [
            (URL(fileURLWithPath: "/Applications"), .applications),
            (URL(fileURLWithPath: "/System/Applications"), .systemApplications),
            (URL(fileURLWithPath: "/System/Applications/Utilities"), .systemApplications),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), .userApplications)
        ]
    }

    private func applications(in root: URL, source: ApplicationSource) -> [InstalledApplication] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var applications: [InstalledApplication] = []

        for case let url as URL in enumerator where url.pathExtension == "app" {
            guard let application = installedApplication(at: url, source: source, preferredTitle: nil) else {
                continue
            }

            applications.append(application)
        }

        return applications
    }

    private func installedApplication(
        at url: URL,
        source: ApplicationSource,
        preferredTitle: String?
    ) -> InstalledApplication? {
        guard let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") != nil else {
            return nil
        }

        if let backgroundOnly = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool,
           backgroundOnly {
            return nil
        }

        let title = preferredTitle?.nilIfBlank
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? fileManager.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")

        return InstalledApplication(
            title: title,
            bundleIdentifier: bundle.bundleIdentifier,
            url: url,
            source: source
        )
    }

    private func preferred(
        _ candidate: InstalledApplication,
        over existing: InstalledApplication?
    ) -> InstalledApplication {
        guard let existing else {
            return candidate
        }

        if existing.source == .workspace && candidate.source != .workspace {
            return candidate
        }

        if candidate.source == .userApplications && existing.source != .userApplications {
            return candidate
        }

        return existing
    }
}
