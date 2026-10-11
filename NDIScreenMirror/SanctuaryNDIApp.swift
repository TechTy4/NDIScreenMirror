import SwiftUI

@main
struct SanctuaryNDIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        AppDelegate.appState = state
        Task { @MainActor in await state.launch() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(appState)
        } label: {
            Image(systemName: appState.status.symbolName)
                .accessibilityLabel("Sanctuary NDI: \(appState.status.rawValue)")
        }
        .menuBarExtraStyle(.menu)

    }
}

/// Opening the app again from Finder or Launchpad shows Settings instead of doing nothing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var appState: AppState?

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Self.appState?.openSettings() }
        return true
    }
}
