import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draftSourceName = ""
    @State private var draftPassword = ""

    var body: some View {
        TabView(selection: $appState.settingsTab) {
            generalTab.tabItem { Label("General", systemImage: "gear") }.tag(SettingsTab.general)
            displaysTab.tabItem { Label("Displays", systemImage: "display.2") }.tag(SettingsTab.displays)
            projectorTab.tabItem { Label("Projector", systemImage: "projector") }.tag(SettingsTab.projector)
            supportTab.tabItem { Label("Support", systemImage: "wrench.and.screwdriver") }.tag(SettingsTab.support)
        }
        .padding(18)
        .frame(width: 650, height: 590)
        .onAppear {
            draftSourceName = appState.preferences.sourceName
            draftPassword = appState.magewellPassword
        }
        .onDisappear {
            saveSourceName()
            appState.saveMagewellPassword(draftPassword)
        }
    }

    private var generalTab: some View {
        Form {
            Section("Room setup") {
                TextField("Input monitor label", text: preferenceBinding(\.inputDisplayLabel))
                Text("This friendly name is shown in the startup wizard. The default is Left/Projector Monitor.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch Sanctuary NDI at login", isOn: Binding(
                    get: { appState.preferences.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
            }

            Section("Current session") {
                LabeledContent("Mode", value: appState.activeMode?.title ?? "Waiting for startup wizard")
                LabeledContent("Status", value: appState.status.rawValue)
                LabeledContent("Confidence monitor", value: appState.confidenceMirrorEnabled ? "Mirroring" : "Not mirrored")
                Button("Run Startup Wizard…") { appState.openStartupWizard() }
            }
        }
        .formStyle(.grouped)
    }

    private var displaysTab: some View {
        Form {
            Section("Monitor roles") {
                Picker("Input monitor", selection: inputDisplaySelection) {
                    Text("Not selected").tag(Optional<CGDirectDisplayID>.none)
                    ForEach(appState.displayManager.displays) { display in
                        Text(display.displayName).tag(Optional(display.id))
                    }
                }
                Picker("Confidence monitor", selection: confidenceDisplaySelection) {
                    Text("Not selected").tag(Optional<CGDirectDisplayID>.none)
                    ForEach(appState.displayManager.displays) { display in
                        Text(display.displayName).tag(Optional(display.id))
                    }
                }
                if inputDisplaySelection.wrappedValue == confidenceDisplaySelection.wrappedValue,
                   inputDisplaySelection.wrappedValue != nil {
                    Label("The input and confidence monitors must be different.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("Refresh Connected Monitors") { Task { await appState.displayManager.refresh() } }
            }

            Section("Monitor NDI feed") {
                TextField("NDI source name", text: $draftSourceName).onSubmit { saveSourceName() }
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
        }
        .formStyle(.grouped)
    }

    private var projectorTab: some View {
        Form {
            Section("Automatic projector control") {
                Toggle("Let Sanctuary NDI choose the projector source", isOn: preferenceBinding(\.magewellEnabled))
                TextField("Receiver address or IP", text: preferenceBinding(\.magewellAddress))
                TextField("Username", text: preferenceBinding(\.magewellUsername))
                SecureField("Password", text: $draftPassword)
                    .onSubmit { appState.saveMagewellPassword(draftPassword) }
                Text("The password is stored in this Mac’s Keychain and is never written to the app or repository.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("How sources are identified") {
                TextField("ProPresenter source contains", text: preferenceBinding(\.proPresenterSourceMatch))
                TextField("Monitor source contains", text: preferenceBinding(\.screenMirrorSourceMatch))
                Text("Use a distinctive portion of each NDI source name. Matching ignores capitalization and requires one unambiguous result.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Connection test") {
                HStack {
                    Button("Save Password & Test") {
                        appState.saveMagewellPassword(draftPassword)
                        appState.testMagewellConnection()
                    }
                    Text(appState.receiverTestMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var supportTab: some View {
        Form {
            Section("Permissions and recovery") {
                Button("Request Screen Recording Permission") { appState.requestScreenPermission() }
                Button("Open Screen Recording Settings") { appState.openScreenRecordingSettings() }
                Button("Restart Monitor Broadcast") { Task { await appState.restartBroadcast() } }
            }
            Section("Diagnostics") {
                Button("Copy Diagnostics") { appState.copyDiagnostics() }
                Text("Diagnostics include configuration and status, but never screen contents or passwords.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("Learn about NDI®", destination: URL(string: "https://ndi.video")!)
                Text("NDI® is a registered trademark of Vizrt NDI AB.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var inputDisplaySelection: Binding<CGDirectDisplayID?> {
        Binding(
            get: {
                guard let saved = appState.preferences.selectedDisplay else { return nil }
                return DisplayIdentity.bestMatch(for: saved, in: appState.displayManager.displays)?.id
            },
            set: { id in
                guard let id, let display = appState.displayManager.displays.first(where: { $0.id == id }) else { return }
                appState.select(display)
            }
        )
    }

    private func preferenceBinding<Value>(_ keyPath: ReferenceWritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.preferences[keyPath: keyPath] },
            set: { appState.preferences[keyPath: keyPath] = $0 }
        )
    }

    private var confidenceDisplaySelection: Binding<CGDirectDisplayID?> {
        Binding(
            get: {
                guard let saved = appState.preferences.confidenceDisplay else { return nil }
                return DisplayIdentity.bestMatch(for: saved, in: appState.displayManager.displays)?.id
            },
            set: { id in
                let display = id.flatMap { value in appState.displayManager.displays.first(where: { $0.id == value }) }
                appState.selectConfidenceDisplay(display)
            }
        )
    }

    private func saveSourceName() {
        let trimmed = draftSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != appState.preferences.sourceName else { return }
        appState.preferences.sourceName = trimmed
        appState.settingsChanged(recreateSender: true)
    }
}
