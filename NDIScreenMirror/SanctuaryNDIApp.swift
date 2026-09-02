import SwiftUI

@main
struct SanctuaryNDIApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
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
