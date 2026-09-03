import AppKit
import SwiftUI

@MainActor
final class WizardWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onFinish: () -> Void

    init(appState: AppState, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        let hostingController = NSHostingController(rootView: StartupWizardView().environmentObject(appState))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sanctuary NDI Setup"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        super.init()
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isEnabled = false
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish() {
        window.orderOut(nil)
        onFinish()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
}
