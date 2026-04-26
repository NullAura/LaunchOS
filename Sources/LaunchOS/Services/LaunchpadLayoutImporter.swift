import Foundation
import SQLite3

enum LaunchpadLayoutImporterError: Error {
    case databaseNotFound
    case openFailed(String)
    case prepareFailed(String)
}

final class LaunchpadLayoutImporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func importLayoutIfAvailable() throws -> ImportedLaunchpadLayout? {
        guard let databaseURL = candidateDatabaseURLs().first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }

        return try withDatabase(at: databaseURL) { database in
            let rootID = try intValue(
                database: database,
                sql: "SELECT value FROM dbinfo WHERE key = 'launchpad_root' LIMIT 1;"
            ) ?? 1

            let pages = try rootPages(database: database, rootID: rootID)
                .compactMap { page -> ImportedLaunchpadPage? in
                    let items = try importedItems(database: database, parentID: page.id, visitedFolders: [])
                    guard !items.isEmpty else {
                        return nil
                    }

                    return ImportedLaunchpadPage(id: page.id, order: page.order, items: items)
                }

            guard !pages.isEmpty else {
                return nil
            }

            return ImportedLaunchpadLayout(
                databasePath: databaseURL.path(percentEncoded: false),
                pages: pages
            )
        }
    }

    private func candidateDatabaseURLs() -> [URL] {
        guard let darwinUserDirectory = darwinUserDirectory() else {
            return []
        }

        let databaseDirectory = darwinUserDirectory
            .appendingPathComponent("com.apple.dock.launchpad")
            .appendingPathComponent("db")

        return [
            databaseDirectory.appendingPathComponent("db"),
            databaseDirectory.appendingPathComponent("db.db")
        ]
    }

    private func darwinUserDirectory() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        process.arguments = ["DARWIN_USER_DIR"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func withDatabase<T>(at url: URL, body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database {
                sqlite3_close(database)
            }

            throw LaunchpadLayoutImporterError.openFailed(message)
        }

        defer {
            sqlite3_close(database)
        }

        return try body(database)
    }

    private func rootPages(database: OpaquePointer, rootID: Int) throws -> [(id: Int, order: Int)] {
        try rows(
            database: database,
            sql: "SELECT rowid, ordering FROM items WHERE parent_id = ? AND type = 3 ORDER BY ordering ASC;",
            integers: [rootID]
        ) { statement in
            (
                id: Int(sqlite3_column_int64(statement, 0)),
                order: Int(sqlite3_column_int64(statement, 1))
            )
        }
    }

    private func importedItems(
        database: OpaquePointer,
        parentID: Int,
        visitedFolders: Set<Int>
    ) throws -> [ImportedLaunchpadItem] {
        try rows(
            database: database,
            sql: """
                SELECT i.rowid, i.type,
                       COALESCE(a.title, d.title, ''),
                       COALESCE(a.bundleid, d.bundleid, ''),
                       COALESCE(g.title, ''),
                       a.bookmark
                FROM items i
                LEFT JOIN apps a ON a.item_id = i.rowid
                LEFT JOIN downloading_apps d ON d.item_id = i.rowid
                LEFT JOIN groups g ON g.item_id = i.rowid
                WHERE i.parent_id = ? AND i.type IN (2, 4, 5)
                ORDER BY i.ordering ASC;
                """,
            integers: [parentID]
        ) { statement in
            let rowID = Int(sqlite3_column_int64(statement, 0))
            let type = Int(sqlite3_column_int64(statement, 1))
            let title = text(statement: statement, column: 2)
            let bundleID = text(statement: statement, column: 3)
            let folderTitle = text(statement: statement, column: 4)
            let bookmarkURL = bookmarkURL(statement: statement, column: 5)

            if type == 2 {
                guard !visitedFolders.contains(rowID) else {
                    return nil
                }

                let apps = try folderApps(
                    database: database,
                    folderID: rowID,
                    visitedFolders: visitedFolders.union([rowID])
                )

                guard !apps.isEmpty else {
                    return nil
                }

                return .folder(
                    ImportedLaunchpadFolder(
                        id: rowID,
                        title: folderTitle.nilIfBlank ?? "文件夹",
                        apps: apps
                    )
                )
            }

            guard let cleanBundleID = bundleID.nilIfBlank else {
                return nil
            }

            return .app(
                ImportedLaunchpadApp(
                    id: rowID,
                    title: title.nilIfBlank ?? cleanBundleID,
                    bundleIdentifier: cleanBundleID,
                    url: bookmarkURL
                )
            )
        }
        .compactMap { $0 }
    }

    private func folderApps(
        database: OpaquePointer,
        folderID: Int,
        visitedFolders: Set<Int>
    ) throws -> [ImportedLaunchpadApp] {
        let folderPages = try rows(
            database: database,
            sql: "SELECT rowid FROM items WHERE parent_id = ? AND type = 3 ORDER BY ordering ASC;",
            integers: [folderID]
        ) { statement in
            Int(sqlite3_column_int64(statement, 0))
        }

        var apps: [ImportedLaunchpadApp] = []

        for pageID in folderPages {
            let pageItems = try importedItems(database: database, parentID: pageID, visitedFolders: visitedFolders)
            for item in pageItems {
                switch item {
                case .app(let app):
                    apps.append(app)
                case .folder(let folder):
                    apps.append(contentsOf: folder.apps)
                }
            }
        }

        return apps
    }

    private func intValue(database: OpaquePointer, sql: String) throws -> Int? {
        try rows(database: database, sql: sql, integers: []) { statement in
            Int(sqlite3_column_int64(statement, 0))
        }
        .first
    }

    private func rows<T>(
        database: OpaquePointer,
        sql: String,
        integers: [Int],
        transform: (OpaquePointer) throws -> T
    ) throws -> [T] {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LaunchpadLayoutImporterError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        for (index, value) in integers.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), sqlite3_int64(value))
        }

        var output: [T] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            output.append(try transform(statement))
        }

        return output
    }

    private func text(statement: OpaquePointer, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else {
            return ""
        }

        return String(cString: pointer)
    }

    private func bookmarkURL(statement: OpaquePointer, column: Int32) -> URL? {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, column) else {
            return nil
        }

        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0 else {
            return nil
        }

        let data = Data(bytes: bytes, count: length)
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
