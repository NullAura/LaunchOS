import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var escapeMonitor: Any?
    private var originalPresentationOptions: NSApplication.PresentationOptions = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        originalPresentationOptions = NSApp.presentationOptions
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installEscapeMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }

        NSApp.presentationOptions = originalPresentationOptions
    }

    func applicationDidResignActive(_ notification: Notification) {
        NotificationCenter.default.post(name: .launchOSExitRequested, object: nil)
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NotificationCenter.default.post(name: .launchOSExitRequested, object: nil)
                return nil
            }

            return event
        }
    }
}
