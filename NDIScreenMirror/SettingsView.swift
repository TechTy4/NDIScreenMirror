import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draftSourceName = ""
    @State private var sourceNameMessage: String?
    @State private var draftPassword = ""
    @State private var supportMessage: String?
    @State private var confirmingReset = false

    var body: some View {
        TabView(selection: $appState.settingsTab) {
            generalTab.tabItem { Label("General", systemImage: "gear") }.tag(SettingsTab.general)
            displaysTab.tabItem { Label("Displays", systemImage: "display.2") }.tag(SettingsTab.displays)
            projectorTab.tabItem { Label("Projector", systemImage: "projector") }.tag(SettingsTab.projector)
            supportTab.tabItem { Label("Support", systemImage: "wrench.and.screwdriver") }.tag(SettingsTab.support)
        }
        .padding(18)
        .frame(width: 680, height: 640)
        .onAppear(perform: loadDrafts)
        .onDisappear {
            saveSourceName()
            appState.saveMagewellPassword(draftPassword)
        }
    }

    private func loadDrafts() {
        draftSourceName = appState.preferences.sourceName
        draftPassword = appState.magewellPassword
        sourceNameMessage = nil
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section("Current session") {
                LabeledContent("Projector shows", value: appState.activeMode.map(appState.title(for:)) ?? "Not chosen yet")
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        feedRow("Projector screen feed", broadcast: appState.projectorBroadcast)
                        feedRow("User screen feed", broadcast: appState.userBroadcast)
                    }
                }
                LabeledContent("Confidence monitor", value: appState.confidenceStatus)
                Button(appState.preferences.screenConfigurationMenuTitle) { appState.openStartupWizard() }
            }

            Section("Room setup") {
                TextField("Configure Screens menu label", text: preferenceBinding(\.screenConfigurationLabel))
                Text("Changes the menu item that opens screen setup. Leave blank to use Configure Screens.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Input monitor label", text: preferenceBinding(\.inputDisplayLabel))
                Text("This friendly name is shown in the startup wizard. The default is Left/Projector Monitor.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch Sanctuary NDI at login", isOn: Binding(
                    get: { appState.preferences.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
                LabeledContent("Login item") {
                    HStack {
                        Text(LoginItemManager.statusDescription)
                            .foregroundStyle(LoginItemManager.needsApproval ? .orange : .secondary)
                        Button("Open Login Items…") { appState.openLoginItemsSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func feedRow(_ title: String, broadcast: MonitorBroadcast) -> some View {
        let receivers = broadcast.sender.connections
        return LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Label(broadcast.status.rawValue, systemImage: broadcast.status.symbolName)
                    .foregroundStyle(broadcast.status == .broadcasting ? .green : .orange)
                Text(broadcast.status == .broadcasting ? "\(receivers) receiver\(receivers == 1 ? "" : "s") connected" : broadcast.detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Displays

    private var displaysTab: some View {
        Form {
            Section("Monitor roles") {
                DisplayPicker(title: "Input monitor (\(appState.preferences.inputDisplayTitle))", placeholder: "Not selected",
                              displays: appState.displayManager.displays,
                              selection: appState.resolvedDisplay(appState.preferences.selectedDisplay)?.id) { display in
                    if let display { appState.select(display) }
                }
                DisplayPicker(title: "User screen (operator)", placeholder: "Not selected",
                              displays: appState.displayManager.displays,
                              selection: appState.resolvedDisplay(appState.preferences.userDisplay)?.id) { display in
                    if let display { appState.selectUserDisplay(display) }
                }
                DisplayPicker(title: "Confidence monitor", placeholder: "Not selected",
                              displays: appState.displayManager.displays,
                              selection: appState.resolvedDisplay(appState.preferences.confidenceDisplay)?.id) { display in
                    appState.selectConfidenceDisplay(display)
                }
                if let input = appState.resolvedDisplay(appState.preferences.selectedDisplay),
                   input.id == appState.resolvedDisplay(appState.preferences.confidenceDisplay)?.id {
                    Label("The input and confidence monitors must be different.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(missingRoles, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Identify Screens") { appState.identifyScreens() }
                    Button("Refresh Connected Monitors") { Task { await appState.displayManager.refresh() } }
                }
                Text("Identify Screens shows each monitor's name and role on the monitor itself. Each feed captures only its selected physical screen, never the combined desktop. Selections are saved automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Always-on NDI feeds") {
                LabeledContent("Projector NDI source name") {
                    HStack {
                        TextField("Projector NDI source name", text: $draftSourceName)
                            .labelsHidden()
                            .onSubmit(saveSourceName)
                        Button("Rename", action: saveSourceName)
                            .disabled(draftSourceName.trimmingCharacters(in: .whitespacesAndNewlines) == appState.preferences.sourceName)
                    }
                }
                if let sourceNameMessage {
                    Text(sourceNameMessage).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("User NDI source name", value: appState.preferences.userSourceName)
                LabeledContent("Projector feed", value: appState.projectorBroadcast.detail)
                LabeledContent("User feed", value: appState.userBroadcast.detail)
                Picker("Frame rate", selection: Binding(
                    get: { appState.preferences.frameRate },
                    set: { appState.preferences.frameRate = $0; appState.settingsChanged() }
                )) {
                    Text("60 fps").tag(60)
                    Text("30 fps (lighter on the network)").tag(30)
                }
                Toggle("Show mouse pointer", isOn: Binding(
                    get: { appState.preferences.showsCursor },
                    set: { appState.preferences.showsCursor = $0; appState.settingsChanged() }
                ))
                Text("Both feeds stream continuously, including while ProPresenter is selected or the startup wizard is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var missingRoles: [String] {
        var messages: [String] = []
        if let saved = appState.preferences.selectedDisplay, appState.resolvedDisplay(saved) == nil {
            messages.append("Saved input monitor “\(saved.name)” is not connected.")
        }
        if let saved = appState.preferences.userDisplay, appState.resolvedDisplay(saved) == nil {
            messages.append("Saved User screen “\(saved.name)” is not connected.")
        }
        if let saved = appState.preferences.confidenceDisplay, appState.resolvedDisplay(saved) == nil {
            messages.append("Saved confidence monitor “\(saved.name)” is not connected.")
        }
        return messages
    }

    // MARK: Projector

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
                HStack {
                    Button("Save Password & Test") {
                        appState.saveMagewellPassword(draftPassword)
                        appState.testMagewellConnection()
                    }
                    .disabled(!appState.receiverActionsAvailable)
                    if appState.receiverIsBusy { ProgressView().controlSize(.small) }
                    Text(appState.receiverTestMessage).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("How sources are identified") {
                TextField("ProPresenter source contains", text: preferenceBinding(\.proPresenterSourceMatch))
                if let summary = appState.matchSummary(for: .proPresenter) {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                TextField("Monitor source contains", text: preferenceBinding(\.screenMirrorSourceMatch))
                if let summary = appState.matchSummary(for: .screenMirror) {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Text("Use a distinctive portion of each NDI source name. Matching ignores capitalization and requires one unambiguous result. Renaming the projector feed updates the monitor match automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !appState.discoveredSources.isEmpty {
                Section("Sources the receiver can see") {
                    ForEach(appState.discoveredSources, id: \.name) { source in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.name).textSelection(.enabled)
                                if let address = source.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Use for ProPresenter") { appState.preferences.proPresenterSourceMatch = source.name }
                            Button("Use for Monitor") { appState.preferences.screenMirrorSourceMatch = source.name }
                        }
                    }
                }
            }

            Section("Switch the projector now") {
                HStack {
                    Button("Show ProPresenter") { appState.switchProjector(to: .proPresenter) }
                    Button("Show \(appState.preferences.inputDisplayTitle)") { appState.switchProjector(to: .screenMirror) }
                }
                .disabled(!appState.receiverActionsAvailable || appState.preferences.magewellAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("Sends the source change to the receiver immediately, without the startup wizard. Useful for testing and troubleshooting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Support

    private var supportTab: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    Label(appState.screenPermissionGranted ? "Allowed" : "Not allowed",
                          systemImage: appState.screenPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.screenPermissionGranted ? .green : .orange)
                }
                HStack {
                    Button("Request Permission") { appState.requestScreenPermission() }
                    Button("Open Screen Recording Settings") { appState.openScreenRecordingSettings() }
                }
                Text("macOS sometimes only applies a newly granted permission after the app is reopened. Use Relaunch below.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Recovery") {
                Button("Recheck Availability") { Task { await appState.recheckAvailability() } }
                    .disabled(appState.availabilityIsRechecking || appState.wizardIsWorking)
                Button("Restart Both NDI Broadcasts") { Task { await appState.restartBroadcast() } }
                Button("Relaunch Sanctuary NDI") { appState.relaunch() }
            }

            Section("Diagnostics") {
                HStack {
                    Button("Copy Diagnostics") {
                        appState.copyDiagnostics()
                        supportMessage = "Diagnostics copied to the clipboard."
                    }
                    Button("Copy Recent Log") {
                        supportMessage = "Reading log…"
                        Task {
                            await appState.copyRecentLog()
                            supportMessage = "Recent log copied to the clipboard."
                        }
                    }
                }
                if let supportMessage { Text(supportMessage).font(.caption).foregroundStyle(.secondary) }
                Text("Diagnostics and logs include configuration, display names, and network addresses, but never screen contents or passwords. Review before sharing publicly.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reset") {
                Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
                Text("Restores every setting to its default and removes the saved receiver password. Screen Recording permission is unaffected.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Link("Learn about NDI®", destination: URL(string: "https://ndi.video")!)
                Text("NDI® is a registered trademark of Vizrt NDI AB.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all Sanctuary NDI settings?", isPresented: $confirmingReset) {
            Button("Reset All Settings", role: .destructive) {
                appState.resetAllSettings()
                loadDrafts()
                supportMessage = "All settings were reset."
            }
        } message: {
            Text("Monitor roles, NDI source name, labels, and projector receiver settings including the password will be cleared.")
        }
    }

    // MARK: Helpers

    private func preferenceBinding<Value>(_ keyPath: ReferenceWritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.preferences[keyPath: keyPath] },
            set: { appState.preferences[keyPath: keyPath] = $0 }
        )
    }

    private func saveSourceName() {
        let trimmed = draftSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != appState.preferences.sourceName else { sourceNameMessage = nil; return }
        if let message = appState.renameProjectorSource(trimmed) {
            sourceNameMessage = message
        } else {
            draftSourceName = appState.preferences.sourceName
            sourceNameMessage = "Renamed. The receiver match was updated if it used the old name."
        }
    }
}
