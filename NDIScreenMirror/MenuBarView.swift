import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading) {
            Label(appState.status.rawValue, systemImage: appState.status.symbolName)
                .foregroundStyle(statusColor)
            Text(appState.projectorSummary)
            Text("Projector feed: \(appState.projectorBroadcast.status.rawValue)")
            Text("User feed: \(appState.userBroadcast.status.rawValue)")
            if appState.confidenceMirrorEnabled {
                Text("Confidence monitor: \(appState.confidenceStatus)")
            }
            if !appState.screenPermissionGranted {
                Button("Allow Screen Recording…") { appState.openScreenRecordingSettings() }
            }

            Divider()
            Button(appState.preferences.screenConfigurationMenuTitle) { appState.openStartupWizard() }
            Divider()
            Button("Settings…") { appState.openSettings() }
            Button("About") { appState.showAbout() }
            Divider()
            Button("Quit Sanctuary NDI") { NSApp.terminate(nil) }
        }
        .frame(minWidth: 290)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch appState.status {
        case .broadcasting, .proPresenter: .green
        case .awaitingSetup, .starting, .sleeping: .orange
        default: .red
        }
    }
}
