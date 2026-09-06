import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: BroadcastStatus = .starting
    @Published private(set) var detail = "Preparing broadcast…"
    @Published private(set) var selectedDisplay: DisplayDescriptor?
    @Published private(set) var frameSize: CGSize = .zero
    @Published private(set) var activeMode: ProjectorInputMode?
    @Published private(set) var confidenceMirrorEnabled = false
    @Published private(set) var proPresenterRunning = false
    @Published var wizardIsWorking = false
    @Published var wizardMessage = ""
    @Published var wizardError: String?
    @Published var receiverTestMessage = "Not tested"
    @Published var magewellPassword = KeychainStore.password()
    @Published var settingsTab: SettingsTab = .general

    let preferences = Preferences()
    let displayManager = DisplayManager()
    let projectorBroadcast = MonitorBroadcast()
    let userBroadcast = MonitorBroadcast()
    private var subscriptions = Set<AnyCancellable>()
    private let confidenceMirror = ConfidenceMirrorController()
    private let magewell = MagewellClient()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Application")
    private var isSleeping = false
    private var didLaunch = false
    private var processActivity: NSObjectProtocol?
    private var settingsWindowController: SettingsWindowController?
    private var wizardWindowController: WizardWindowController?

    init() {
        projectorBroadcast.capture.onSampleBuffer = { [weak self] sampleBuffer in
            self?.confidenceMirror.enqueue(sampleBuffer)
        }
        for broadcast in [projectorBroadcast, userBroadcast] {
            broadcast.objectWillChange.sink { [weak self] _ in
                Task { @MainActor in self?.updateBroadcastStatus() }
            }.store(in: &subscriptions)
        }
        preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }.store(in: &subscriptions)
        displayManager.onDisplaysChanged = { [weak self] in
            guard let self else { return }
            self.configureBroadcasts()
            self.objectWillChange.send()
            if self.confidenceMirrorEnabled {
                do { try self.configureConfidenceMirror(enabled: true) }
                catch { self.confidenceMirror.hide(); self.detail = error.localizedDescription }
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.sleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.wake() }
        }
    }

    func launch() async {
        guard !didLaunch else { return }
        didLaunch = true
        ProcessInfo.processInfo.disableAutomaticTermination("Sanctuary NDI continuously mirrors the selected display")
        ProcessInfo.processInfo.disableSuddenTermination()
        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Broadcasting the selected display over NDI"
        )
        logger.info("Sanctuary NDI launched")
        do { try LoginItemManager.setEnabled(preferences.launchAtLogin) }
        catch { logger.error("Launch at login setup failed: \(error.localizedDescription, privacy: .public)") }
        status = .awaitingSetup
        detail = "Choose how the projector should be used."
        await displayManager.refresh()
        refreshProPresenterState()
        openStartupWizard()
    }

    func select(_ display: DisplayDescriptor) {
        logger.info("Display selected from menu: \(display.displayName, privacy: .public), ID \(display.id)")
        selectedDisplay = display
        preferences.selectedDisplay = display.identity
        configureBroadcasts()
        if confidenceMirrorEnabled { try? configureConfidenceMirror(enabled: true) }
    }

    func selectConfidenceDisplay(_ display: DisplayDescriptor?) {
        preferences.confidenceDisplay = display?.identity
        guard activeMode == .screenMirror, confidenceMirrorEnabled else { return }
        do {
            try configureConfidenceMirror(enabled: true)
        } catch {
            detail = error.localizedDescription
        }
    }

    func openStartupWizard() {
        wizardError = nil
        wizardMessage = ""
        if wizardWindowController == nil {
            wizardWindowController = WizardWindowController(appState: self) { [weak self] in
                self?.wizardWindowController = nil
                self?.updateActivationPolicy()
            }
        }
        wizardWindowController?.show()
        updateActivationPolicy()
    }

    func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: self) { [weak self] in
                self?.settingsWindowController = nil
                self?.updateActivationPolicy()
            }
        }
        settingsWindowController?.show()
        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        let hasForegroundWindow = settingsWindowController != nil || wizardWindowController != nil
        NSApp.setActivationPolicy(hasForegroundWindow ? .regular : .accessory)
        if hasForegroundWindow { NSApp.activate(ignoringOtherApps: true) }
    }

    func selectUserDisplay(_ display: DisplayDescriptor) {
        preferences.userDisplay = display.identity
        configureBroadcasts()
    }

    private func configureBroadcasts(force: Bool = false) {
        if preferences.userDisplay == nil, let main = displayManager.displays.first(where: { $0.isMain }) {
            preferences.userDisplay = main.identity
        }
        if preferences.selectedDisplay == nil, displayManager.displays.count == 1 {
            preferences.selectedDisplay = displayManager.displays[0].identity
        }
        selectedDisplay = preferences.selectedDisplay.flatMap { DisplayIdentity.bestMatch(for: $0, in: displayManager.displays) }
        let userDisplay = preferences.userDisplay.flatMap { DisplayIdentity.bestMatch(for: $0, in: displayManager.displays) }
        projectorBroadcast.configure(display: selectedDisplay, name: preferences.sourceName,
                                     frameRate: preferences.frameRate, cursor: preferences.showsCursor, sleeping: isSleeping, force: force)
        userBroadcast.configure(display: userDisplay, name: preferences.userSourceName,
                                frameRate: preferences.frameRate, cursor: preferences.showsCursor, sleeping: isSleeping, force: force)
        frameSize = selectedDisplay.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    private func updateBroadcastStatus() {
        let feeds = [projectorBroadcast, userBroadcast]
        if isSleeping { status = .sleeping }
        else if let issue = feeds.first(where: { $0.status != .broadcasting }) { status = issue.status }
        else { status = .broadcasting }
        let count = feeds.filter { $0.status == .broadcasting }.count
        detail = "\(count)/2 screen feeds running · Projector: \(activeMode?.title ?? "Choose in Startup Wizard")"
        objectWillChange.send()
    }

    func restartBroadcast() async {
        configureBroadcasts(force: true)
        await projectorBroadcast.waitUntilSettled()
        await userBroadcast.waitUntilSettled()
        updateBroadcastStatus()
    }

    func settingsChanged(recreateSender: Bool = false) {
        configureBroadcasts()
    }

    private func sleep() async {
        isSleeping = true
        configureBroadcasts()
        await projectorBroadcast.waitUntilSettled()
        await userBroadcast.waitUntilSettled()
        confidenceMirror.hide()
        updateBroadcastStatus()
    }

    private func wake() async {
        isSleeping = false
        try? await Task.sleep(for: .seconds(2))
        await displayManager.refresh()
    }

    func completeWizard(mode: ProjectorInputMode, mirrorToConfidenceDisplay: Bool) async {
        guard !wizardIsWorking else { return }
        wizardIsWorking = true
        wizardError = nil
        defer { wizardIsWorking = false }
        do {
            switch mode {
            case .proPresenter:
                refreshProPresenterState()
                guard proPresenterRunning else { throw StartupWorkflowError.proPresenterNotRunning }
                wizardMessage = "Connecting the projector to ProPresenter…"
                confidenceMirrorEnabled = false
                confidenceMirror.hide()
                if preferences.magewellEnabled {
                    _ = try await selectReceiverSourceWithRetry(matching: preferences.proPresenterSourceMatch)
                }
                activeMode = .proPresenter
                updateBroadcastStatus()
            case .screenMirror:
                guard CGPreflightScreenCaptureAccess() else {
                    _ = CGRequestScreenCaptureAccess()
                    throw StartupWorkflowError.screenPermissionRequired
                }
                guard let saved = preferences.selectedDisplay,
                      DisplayIdentity.bestMatch(for: saved, in: displayManager.displays) != nil else {
                    throw StartupWorkflowError.inputDisplayMissing
                }
                confidenceMirrorEnabled = mirrorToConfidenceDisplay
                try configureConfidenceMirror(enabled: mirrorToConfidenceDisplay)
                wizardWindowController?.show()
                wizardMessage = "Starting the monitor feed…"
                configureBroadcasts()
                await projectorBroadcast.waitUntilSettled()
                guard projectorBroadcast.status == .broadcasting else { throw StartupWorkflowError.broadcastFailed(detail) }
                if preferences.magewellEnabled {
                    wizardMessage = "Connecting the projector to the monitor feed…"
                    _ = try await selectReceiverSourceWithRetry(matching: preferences.screenMirrorSourceMatch)
                }
                activeMode = .screenMirror
            }
            updateBroadcastStatus()
            wizardMessage = "Ready"
            wizardWindowController?.finish()
            wizardWindowController = nil
            updateActivationPolicy()
        } catch {
            wizardError = error.localizedDescription
        }
    }

    private func configureConfidenceMirror(enabled: Bool) throws {
        guard enabled else {
            confidenceMirror.hide()
            return
        }
        guard let input = preferences.selectedDisplay.flatMap({ DisplayIdentity.bestMatch(for: $0, in: displayManager.displays) }),
              let confidence = preferences.confidenceDisplay.flatMap({ DisplayIdentity.bestMatch(for: $0, in: displayManager.displays) }) else {
            throw StartupWorkflowError.confidenceDisplayMissing
        }
        guard input.id != confidence.id else { throw ConfidenceMirrorError.sameDisplay }
        try confidenceMirror.show(on: confidence)
    }

    private func selectReceiverSourceWithRetry(matching name: String) async throws -> MagewellSource {
        var lastError: Error = MagewellError.sourceNotFound(name, [])
        for attempt in 0..<15 {
            do {
                return try await magewell.selectSource(
                    matching: name,
                    address: preferences.magewellAddress,
                    username: preferences.magewellUsername,
                    password: magewellPassword
                )
            } catch let error as MagewellError {
                lastError = error
                guard case .sourceNotFound = error, attempt < 14 else { throw error }
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw lastError
    }

    func testMagewellConnection() {
        receiverTestMessage = "Testing…"
        Task {
            do {
                let sources = try await magewell.sources(
                    address: preferences.magewellAddress,
                    username: preferences.magewellUsername,
                    password: magewellPassword
                )
                receiverTestMessage = "Connected — \(sources.count) NDI source\(sources.count == 1 ? "" : "s") found"
            } catch {
                receiverTestMessage = error.localizedDescription
            }
        }
    }

    func saveMagewellPassword(_ password: String) {
        magewellPassword = password
        do { try KeychainStore.setPassword(password) }
        catch { receiverTestMessage = "Could not save password: \(error.localizedDescription)" }
    }

    func refreshProPresenterState() {
        proPresenterRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.localizedCaseInsensitiveContains("renewedvision.ProPresenter") == true ||
            $0.localizedName?.localizedCaseInsensitiveContains("ProPresenter") == true
        }
    }

    func openProPresenter() {
        let bundleIdentifiers = [
            "com.renewedvision.ProPresenter",
            "com.renewedvision.ProPresenter7",
            "com.renewedvision.ProPresenter6"
        ]
        let url = bundleIdentifiers.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            ?? (FileManager.default.fileExists(atPath: "/Applications/ProPresenter.app") ? URL(fileURLWithPath: "/Applications/ProPresenter.app") : nil)
        if let url {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            wizardError = "ProPresenter is not installed in the Applications folder."
        }
        refreshProPresenterState()
    }

    func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
        Task { await displayManager.refresh() }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        preferences.launchAtLogin = enabled
        do { try LoginItemManager.setEnabled(enabled) }
        catch { detail = "Could not update Launch at Login: \(error.localizedDescription)" }
    }

    func copyDiagnostics() {
        let display = selectedDisplay?.displayName ?? preferences.selectedDisplay?.name ?? "None"
        let identity = selectedDisplay?.identity.uuid ?? preferences.selectedDisplay?.uuid ?? "None"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let text = """
        Sanctuary NDI \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(SystemInfo.architecture)
        Status: \(status.rawValue)
        Selected display: \(display)
        Display UUID: \(identity)
        Resolution: \(Int(frameSize.width))×\(Int(frameSize.height))
        Frame rate: \(preferences.frameRate)
        NDI source: \(preferences.sourceName)
        NDI runtime: \(NDISender.runtimeVersion)
        Projector NDI receivers: \(projectorBroadcast.sender.connections)
        Projector feed: \(projectorBroadcast.status.rawValue) — \(projectorBroadcast.detail)
        User display: \(preferences.userDisplay?.name ?? "Not selected")
        User NDI source: \(preferences.userSourceName)
        User NDI receivers: \(userBroadcast.sender.connections)
        User feed: \(userBroadcast.status.rawValue) — \(userBroadcast.detail)
        Operating mode: \(activeMode?.title ?? "Startup wizard")
        Confidence mirror: \(confidenceMirrorEnabled ? "on" : "off")
        Projector control: \(preferences.magewellEnabled ? "enabled" : "disabled")
        Projector receiver: \(preferences.magewellAddress.isEmpty ? "not configured" : preferences.magewellAddress)
        Screen recording permission: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")
        Launch at Login: \(LoginItemManager.statusDescription)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSMutableAttributedString(
            string: "Streams the projector and operator displays as independent High Bandwidth NDI® sources.\n\nNDI® is a registered trademark of Vizrt NDI AB.\n",
            attributes: [.paragraphStyle: paragraph]
        )
        credits.append(NSAttributedString(
            string: "Learn more at ndi.video",
            attributes: [.link: URL(string: "https://ndi.video")!, .paragraphStyle: paragraph]
        ))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum BroadcastError: LocalizedError { case displayDisappeared }

enum StartupWorkflowError: LocalizedError {
    case proPresenterNotRunning
    case screenPermissionRequired
    case inputDisplayMissing
    case confidenceDisplayMissing
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .proPresenterNotRunning: "Open ProPresenter before continuing."
        case .screenPermissionRequired: "Allow Screen Recording in System Settings, then return and try again."
        case .inputDisplayMissing: "Choose the Left/Projector Monitor in Settings before continuing."
        case .confidenceDisplayMissing: "Choose the confidence monitor in Settings, or turn off duplication."
        case .broadcastFailed(let detail): "The monitor feed could not start. \(detail)"
        }
    }
}

enum SystemInfo {
    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
