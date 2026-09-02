import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let rootView = SettingsView().environmentObject(appState)
        let hostingController = NSHostingController(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sanctuary NDI Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        super.init()
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose()
    }
}
