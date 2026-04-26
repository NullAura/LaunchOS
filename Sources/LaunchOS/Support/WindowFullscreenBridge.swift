import AppKit
import SwiftUI

struct WindowFullscreenBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfiguringView {
        WindowConfiguringView()
    }

    func updateNSView(_ nsView: WindowConfiguringView, context: Context) {
        nsView.configureWindowIfNeeded()
    }
}

final class WindowConfiguringView: NSView {
    private weak var configuredWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfNeeded()
    }

    func configureWindowIfNeeded() {
        guard let window else {
            return
        }

        let screen = window.screen ?? NSScreen.main
        window.title = "LaunchOS"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary, .transient]
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        if configuredWindow !== window {
            installObservers(for: window)
            window.minSize = NSSize(width: 640, height: 420)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        configuredWindow = window
        NSApp.presentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
        pinWindowToScreen(window, screen: screen)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else {
                return
            }

            self?.pinWindowToScreen(window, screen: window.screen ?? NSScreen.main)
        }
    }

    private func installObservers(for window: NSWindow) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []

        let center = NotificationCenter.default
        let windowNotifications: [NSNotification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didBecomeKeyNotification
        ]

        for notification in windowNotifications {
            observers.append(
                center.addObserver(forName: notification, object: window, queue: .main) { [weak self, weak window] _ in
                    guard let window else {
                        return
                    }

                    self?.pinWindowToScreen(window, screen: window.screen ?? NSScreen.main)
                }
            )
        }

        observers.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self, weak window] _ in
                guard let window else {
                    return
                }

                self?.pinWindowToScreen(window, screen: window.screen ?? NSScreen.main)
            }
        )
    }

    private func pinWindowToScreen(_ window: NSWindow, screen: NSScreen?) {
        guard let frame = (screenContainingMouse() ?? screen ?? NSScreen.main)?.frame else {
            return
        }

        window.minSize = frame.size
        window.maxSize = frame.size
        window.setFrame(frame, display: true, animate: false)
        window.contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}
