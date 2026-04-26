import SwiftUI

@main
struct LaunchOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新应用") {
                    NotificationCenter.default.post(name: .launchOSRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
