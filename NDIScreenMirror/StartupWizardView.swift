import SwiftUI

struct StartupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var mode: ProjectorInputMode?
    @State private var mirrorToConfidenceDisplay = false
    @State private var showTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Divider()
            if step == 0 { inputStep } else { mirrorStep }
            Spacer(minLength: 8)
            statusArea
            Divider()
            footer
        }
        .padding(28)
        .frame(width: 680, height: 520)
        .task {
            while !Task.isCancelled {
                appState.refreshProPresenterState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: step == 0 ? "rectangle.inset.filled.and.person.filled" : "rectangle.on.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(step == 0 ? "What should the projector show?" : "Duplicate it on the confidence monitor?")
                    .font(.title2.bold())
                Text(step == 0 ? "Choose how you plan to use the room today." : "This is useful when the same material should appear on both sides.")
                    .foregroundStyle(.secondary)
            }
        }
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
                    Label("ProPresenter must be open before continuing.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open ProPresenter") { appState.openProPresenter() }
                }
            }
            if mode == .screenMirror {
                Label(
                    resolvedInputName ?? "No input monitor selected",
                    systemImage: resolvedInputName == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(resolvedInputName == nil ? .orange : .secondary)
                if resolvedInputName == nil {
                    Button("Choose Input Monitor in Settings…") { appState.openSettings(tab: .displays) }
                }
            }
            if !receiverConfigurationReady {
                HStack {
                    Label("Projector control needs to be configured before continuing.", systemImage: "gearshape.fill")
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
                let confidenceName = resolvedConfidenceName
                Label(confidenceName ?? "No confidence monitor selected", systemImage: confidenceName == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(confidenceName == nil ? .orange : .secondary)
                if confidenceName == nil {
                    Button("Choose Monitor in Settings…") { appState.openSettings(tab: .displays) }
                }
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
                    Text(candidate == .screenMirror ? appState.preferences.inputDisplayLabel : candidate.title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == candidate ? Color.accentColor : .secondary)
            }
            .padding(16)
            .background(mode == candidate ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
            .background(mirrorToConfidenceDisplay == enabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var statusArea: some View {
        if let error = appState.wizardError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.red)
        } else if appState.wizardIsWorking {
            HStack { ProgressView(); Text(appState.wizardMessage).foregroundStyle(.secondary) }
        } else {
            DisclosureGroup("Technical details", isExpanded: $showTechnicalDetails) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Monitor NDI source: \(appState.preferences.screenMirrorSourceMatch)")
                    Text("ProPresenter source match: \(appState.preferences.proPresenterSourceMatch)")
                    Text("Projector receiver: \(appState.preferences.magewellAddress.isEmpty ? "Not configured" : appState.preferences.magewellAddress)")
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 5)
            }
            .font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { appState.openSettings() }
            Spacer()
            if step == 1 { Button("Back") { step = 0 } }
            Button(step == 0 && mode == .screenMirror ? "Next" : "Start") {
                guard let mode else { return }
                if step == 0 && mode == .screenMirror {
                    step = 1
                } else {
                    Task { await appState.completeWizard(mode: mode, mirrorToConfidenceDisplay: mirrorToConfidenceDisplay) }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                mode == nil || appState.wizardIsWorking ||
                (mode == .proPresenter && !appState.proPresenterRunning) ||
                (mode == .screenMirror && resolvedInputName == nil) ||
                (step == 1 && mirrorToConfidenceDisplay && resolvedConfidenceName == nil) ||
                !receiverConfigurationReady
            )
        }
    }

    private var resolvedInputName: String? {
        guard let saved = appState.preferences.selectedDisplay else { return nil }
        return DisplayIdentity.bestMatch(for: saved, in: appState.displayManager.displays)?.displayName
    }

    private var resolvedConfidenceName: String? {
        guard let saved = appState.preferences.confidenceDisplay else { return nil }
        return DisplayIdentity.bestMatch(for: saved, in: appState.displayManager.displays)?.displayName
    }

    private var receiverConfigurationReady: Bool {
        guard appState.preferences.magewellEnabled else { return true }
        let hasAddress = !appState.preferences.magewellAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let match = mode == .proPresenter ? appState.preferences.proPresenterSourceMatch : appState.preferences.screenMirrorSourceMatch
        return hasAddress && !match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
