import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draftName = ""

    var body: some View {
        Form {
            Section("General") {
                TextField("NDI source name", text: $draftName)
                    .onSubmit { saveName() }
                Toggle("Launch Sanctuary NDI at login", isOn: Binding(
                    get: { appState.preferences.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                LabeledContent("Selected display", value: appState.selectedDisplay?.displayName ?? "Not connected")
            }

            Section("Video") {
                Picker("Frame rate", selection: Binding(
                    get: { appState.preferences.frameRate },
                    set: { appState.preferences.frameRate = $0; appState.settingsChanged() }
                )) {
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                }
                Toggle("Show mouse pointer", isOn: Binding(
                    get: { appState.preferences.showsCursor },
                    set: { appState.preferences.showsCursor = $0; appState.settingsChanged() }
                ))
            }

            Section {
                Link("Learn about NDI®", destination: URL(string: "https://ndi.video")!)
                Text("NDI® is a registered trademark of Vizrt NDI AB.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 350)
        .onAppear { draftName = appState.preferences.sourceName }
        .onChange(of: appState.preferences.sourceName) { value in draftName = value }
        .onDisappear { saveName() }
    }

    private func saveName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != appState.preferences.sourceName else { return }
        appState.preferences.sourceName = trimmed
        appState.settingsChanged(recreateSender: true)
    }
}
