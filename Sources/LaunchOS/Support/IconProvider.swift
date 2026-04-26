import AppKit
import SwiftUI

@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private var cache: [URL: NSImage] = [:]

    func icon(for app: LaunchApp) -> NSImage {
        if let cached = cache[app.url] {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: 256, height: 256)
        cache[app.url] = icon
        return icon
    }
}
