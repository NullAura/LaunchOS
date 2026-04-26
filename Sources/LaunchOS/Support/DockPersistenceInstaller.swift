import AppKit
import Foundation

enum DockPersistenceInstaller {
    private static let installedKey = "LaunchOSDidRequestDockPersistence"

    static func installIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return false
        }

        let appURL = Bundle.main.bundleURL
        let hasRequestedDockPersistence = defaults.bool(forKey: installedKey)

        Task.detached(priority: .utility) {
            if hasRequestedDockPersistence, isAlreadyInDock(appURL: appURL) {
                return
            }

            if isAlreadyInDock(appURL: appURL) || addToDock(appURL: appURL) {
                defaults.set(true, forKey: installedKey)
            }
        }

        return true
    }

    private static func isAlreadyInDock(appURL: URL) -> Bool {
        guard let output = run("/usr/bin/defaults", arguments: ["read", "com.apple.dock", "persistent-apps"]) else {
            return false
        }

        return output.contains(appURL.path)
    }

    private static func addToDock(appURL: URL) -> Bool {
        let path = appURL.path
        let tile = """
        <dict>
          <key>tile-data</key>
          <dict>
            <key>file-data</key>
            <dict>
              <key>_CFURLString</key>
              <string>\(xmlEscaped(path))</string>
              <key>_CFURLStringType</key>
              <integer>0</integer>
            </dict>
            <key>file-label</key>
            <string>LaunchOS</string>
          </dict>
          <key>tile-type</key>
          <string>file-tile</string>
        </dict>
        """

        guard run("/usr/bin/defaults", arguments: ["write", "com.apple.dock", "persistent-apps", "-array-add", tile]) != nil else {
            return false
        }

        _ = run("/usr/bin/killall", arguments: ["Dock"])
        return true
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
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

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
