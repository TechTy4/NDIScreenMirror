import CoreGraphics
import SwiftUI

struct StartupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var mode: ProjectorInputMode?
    @State private var mirrorToConfidenceDisplay = false
    @State private var showTechnicalDetails = false
    @State private var didRestoreLastChoice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            if !appState.screenPermissionGranted { permissionBanner }
            if step == 0 { inputStep } else { mirrorStep }
            Spacer(minLength: 8)
            statusArea
            Divider()
            footer
        }
        .padding(28)
        .frame(width: 680, height: 580)
        .onAppear(perform: restoreLastChoice)
        .task {
            while !Task.isCancelled {
                appState.refreshEnvironmentState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Pre-selects yesterday's answer so a routine startup is a single click on Start.
    private func restoreLastChoice() {
        guard !didRestoreLastChoice else { return }
        didRestoreLastChoice = true
        mode = appState.preferences.lastMode
        mirrorToConfidenceDisplay = appState.preferences.lastMirrorToConfidence
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: step == 0 ? "rectangle.inset.filled.and.person.filled" : "rectangle.on.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(step == 0 ? "What should the projector show?" : "Duplicate it on the confidence monitor?")
                    .font(.title2.bold())
                Text(step == 0 ? "Choose the projector source, then click \(primaryButtonTitle). Both screen feeds keep running for the livestream team." : "This is useful when the same material should appear on both sides.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Recording permission is needed").font(.headline)
                Text("Turn on Sanctuary NDI in System Settings → Privacy & Security → Screen Recording. If macOS asks, relaunch the app afterwards.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Button("Open System Settings") { appState.openScreenRecordingSettings() }
                Button("Relaunch App") { appState.relaunch() }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            choiceCard(
                mode: .proPresenter,
                icon: "play.rectangle.on.rectangle",
                detail: "Best for services and presentations prepared in ProPresenter."
            )
            choiceCard(
                mode: .screenMirror,
                icon: "display",
                detail: "Best for school, guest laptops, web pages, videos, or anything else shown on the input monitor."
            )

            if mode == .proPresenter && !appState.proPresenterRunning {
                HStack {
                    if appState.proPresenterInstalled {
                        Label("ProPresenter isn’t open yet. It will be opened for you when you click Start.", systemImage: "info.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("ProPresenter wasn’t found in Applications. Open it manually first.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Open ProPresenter") { appState.openProPresenter() }
                }
            }
            if mode == .screenMirror {
                displayRoleRow(
                    question: "Which monitor is the \(appState.preferences.inputDisplayTitle)?",
                    identity: appState.preferences.selectedDisplay,
                    excluding: nil
                ) { appState.select($0) }
            }
            if !receiverConfigurationReady {
                HStack {
                    Label("Projector control needs a receiver address and source name.", systemImage: "gearshape.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Projector Settings…") { appState.openSettings(tab: .projector) }
                }
            }
        }
    }

    private var mirrorStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            mirrorCard(enabled: false, title: "Projector only", detail: "Leave the confidence monitor unchanged.", icon: "rectangle")
            mirrorCard(enabled: true, title: "Projector and confidence monitor", detail: "Show a fullscreen duplicate on the configured confidence monitor.", icon: "rectangle.on.rectangle")

            if mirrorToConfidenceDisplay {
                displayRoleRow(
                    question: "Which monitor is the confidence monitor?",
                    identity: appState.preferences.confidenceDisplay,
                    excluding: appState.resolvedDisplay(appState.preferences.selectedDisplay)?.id
                ) { appState.selectConfidenceDisplay($0) }
            }
        }
    }

    /// Shows the saved monitor, or an inline picker when it is not connected or not chosen yet.
    @ViewBuilder
    private func displayRoleRow(question: String, identity: DisplayIdentity?, excluding: CGDirectDisplayID?,
                                select: @escaping (DisplayDescriptor) -> Void) -> some View {
        let resolved = appState.resolvedDisplay(identity)
        if let resolved, resolved.id != excluding {
            HStack {
                Label(resolved.displayName, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                Spacer()
                Button("Identify Screens") { appState.identifyScreens() }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    DisplayPicker(title: question, placeholder: "Choose…", displays: appState.displayManager.displays,
                                  selection: nil) { display in
                        if let display { select(display) }
                    }
                    Button("Identify Screens") { appState.identifyScreens() }
                }
                Text(identity == nil ? "Not chosen yet. Use Identify Screens to see which monitor is which."
                                     : "The saved monitor (\(identity?.name ?? "")) is not connected or is already used as the input monitor.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func choiceCard(mode candidate: ProjectorInputMode, icon: String, detail: String) -> some View {
        Button {
            mode = candidate
            appState.wizardError = nil
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 26)).frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.title(for: candidate)).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == candidate ? Color.accentColor : .secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(mode == candidate ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(appState.wizardIsWorking)
    }

    private func mirrorCard(enabled: Bool, title: String, detail: String, icon: String) -> some View {
        Button {
            mirrorToConfidenceDisplay = enabled
            appState.wizardError = nil
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 24)).frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: mirrorToConfidenceDisplay == enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mirrorToConfidenceDisplay == enabled ? Color.accentColor : .secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(mirrorToConfidenceDisplay == enabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(appState.wizardIsWorking)
    }

    @ViewBuilder private var statusArea: some View {
        if let error = appState.wizardError {
            ScrollView {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 80)
        } else if appState.wizardIsWorking || appState.availabilityIsRechecking {
            HStack { ProgressView().controlSize(.small); Text(appState.availabilityIsRechecking ? "Rechecking screens and NDI feeds…" : appState.wizardMessage).foregroundStyle(.secondary) }
        } else {
            DisclosureGroup("Technical details", isExpanded: $showTechnicalDetails) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Projector feed (\(appState.preferences.sourceName)): \(appState.projectorBroadcast.status.rawValue)")
                    Text("User feed (\(appState.preferences.userSourceName)): \(appState.userBroadcast.status.rawValue) — always running")
                    Text("Receiver match for monitor: \(appState.preferences.screenMirrorSourceMatch)")
                    Text("Receiver match for ProPresenter: \(appState.preferences.proPresenterSourceMatch)")
                    Text("Projector receiver: \(appState.preferences.magewellEnabled ? (appState.preferences.magewellAddress.isEmpty ? "Not configured" : appState.preferences.magewellAddress) : "Automatic control off")")
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                .textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { appState.openSettings() }
            Button("Recheck Availability") { Task { await appState.recheckAvailability() } }
                .disabled(appState.wizardIsWorking || appState.availabilityIsRechecking)
            Spacer()
            if appState.wizardIsWorking {
                Button("Stop Checking") { appState.cancelWizardConnection() }
            }
            if step == 1 {
                Button("Back") { step = 0; appState.wizardError = nil }
                    .disabled(appState.wizardIsWorking)
            }
            Button(primaryButtonTitle) {
                guard let mode else { return }
                if step == 0 && mode == .screenMirror {
                    appState.wizardError = nil
                    step = 1
                } else {
                    appState.beginWizard(mode: mode, mirrorToConfidenceDisplay: mode == .screenMirror && mirrorToConfidenceDisplay)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                mode == nil || appState.wizardIsWorking || appState.availabilityIsRechecking ||
                (mode == .proPresenter && !appState.proPresenterRunning && !appState.proPresenterInstalled) ||
                (mode == .screenMirror && appState.resolvedDisplay(appState.preferences.selectedDisplay) == nil) ||
                (step == 1 && mirrorToConfidenceDisplay && !confidenceReady) ||
                !receiverConfigurationReady
            )
        }
    }

    private var primaryButtonTitle: String {
        if step == 0 && mode == .screenMirror { return "Next" }
        if appState.wizardError != nil && (step == 1 || mode == .proPresenter) { return "Recheck & Retry" }
        if mode == .proPresenter && !appState.proPresenterRunning && appState.proPresenterInstalled { return "Open ProPresenter & Start" }
        return "Start"
    }

    private var confidenceReady: Bool {
        guard let confidence = appState.resolvedDisplay(appState.preferences.confidenceDisplay) else { return false }
        return confidence.id != appState.resolvedDisplay(appState.preferences.selectedDisplay)?.id
    }

    private var receiverConfigurationReady: Bool {
        guard appState.preferences.magewellEnabled else { return true }
        let hasAddress = !appState.preferences.magewellAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let match = mode == .proPresenter ? appState.preferences.proPresenterSourceMatch : appState.preferences.screenMirrorSourceMatch
        return hasAddress && !match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A monitor picker keyed by the current display ID; the saved identity is resolved by the caller.
struct DisplayPicker: View {
    let title: String
    let placeholder: String
    let displays: [DisplayDescriptor]
    let selection: CGDirectDisplayID?
    let onSelect: (DisplayDescriptor?) -> Void

    var body: some View {
        Picker(title, selection: Binding(
            get: { selection },
            set: { id in onSelect(id.flatMap { id in displays.first { $0.id == id } }) }
        )) {
            Text(placeholder).tag(Optional<CGDirectDisplayID>.none)
            ForEach(displays) { display in
                Text(display.displayName).tag(Optional(display.id))
            }
        }
    }
}
