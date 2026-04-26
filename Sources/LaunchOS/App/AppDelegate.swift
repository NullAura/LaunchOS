import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var escapeMonitor: Any?
    private var originalPresentationOptions: NSApplication.PresentationOptions = []
    private var ignoreResignUntil: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        originalPresentationOptions = NSApp.presentationOptions
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installEscapeMonitor()

        if DockPersistenceInstaller.installIfNeeded() {
            ignoreResignUntil = Date().addingTimeInterval(3)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }

        NSApp.presentationOptions = originalPresentationOptions
    }

    func applicationDidResignActive(_ notification: Notification) {
        if let ignoreResignUntil, Date() < ignoreResignUntil {
            return
        }

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
