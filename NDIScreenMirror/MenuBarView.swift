import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading) {
            Label(appState.status.rawValue, systemImage: appState.status.symbolName)
                .foregroundStyle(appState.status == .broadcasting ? .green : .orange)
            Text(appState.detail).font(.caption).foregroundStyle(.secondary)

            Divider()
            Text("Mirror Display")
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.displayManager.displays.isEmpty {
                Text("No displays available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.displayManager.displays) { display in
                    Button {
                        appState.select(display)
                    } label: {
                        Label(
                            display.displayName,
                            systemImage: display.id == appState.selectedDisplay?.id
                                ? "checkmark.circle.fill"
                                : "display"
                        )
                    }
                }
            }

            Button("Refresh Displays") { Task { await appState.displayManager.refresh() } }

            if appState.status == .permissionRequired {
                Button("Request Screen Recording Permission") { appState.requestScreenPermission() }
                Button("Open Screen Recording Settings") { appState.openScreenRecordingSettings() }
            }

            Button("Restart Broadcast") { Task { await appState.restartBroadcast() } }
            Divider()
            Button("Copy Diagnostics") { appState.copyDiagnostics() }
            Button("Settings…") { appState.openSettings() }
            Button("About Sanctuary NDI") { appState.showAbout() }
            Divider()
            Button("Quit Sanctuary NDI") { NSApp.terminate(nil) }
        }
        .frame(minWidth: 285)
        .padding(.vertical, 4)
    }
}
