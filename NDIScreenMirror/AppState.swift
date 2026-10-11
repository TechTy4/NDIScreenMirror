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
    @Published private(set) var screenPermissionGranted = CGPreflightScreenCaptureAccess()
    @Published var wizardIsWorking = false
    @Published var wizardMessage = ""
    @Published var wizardError: String?
    @Published private(set) var availabilityIsRechecking = false
    @Published var receiverTestMessage = "Not tested"
    @Published private(set) var receiverIsBusy = false
    @Published private(set) var discoveredSources: [MagewellSource] = []
    @Published var magewellPassword = KeychainStore.password()
    @Published var settingsTab: SettingsTab = .general

    let preferences = Preferences()
    let displayManager = DisplayManager()
    let projectorBroadcast = MonitorBroadcast()
    let userBroadcast = MonitorBroadcast()
    private var subscriptions = Set<AnyCancellable>()
    private let confidenceMirror = ConfidenceMirrorController()
    private let magewell = MagewellClient()
    private let screenIdentifier = ScreenIdentifier()
    private static let reopenNotification = Notification.Name("org.sanctuary.SanctuaryNDI.reopen")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Application")
    private var isSleeping = false
    private var didLaunch = false
    private var processActivity: NSObjectProtocol?
    private var settingsWindowController: SettingsWindowController?
    private var wizardWindowController: WizardWindowController?
    private var availabilityTask: Task<Void, Never>?
    private var wizardTask: Task<Void, Never>?
    /// Settings-initiated receiver work (test or manual switch). The wizard waits for it,
    /// and Settings actions are disabled while the wizard runs, so selections never interleave.
    private var receiverTask: Task<Void, Never>?

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
            if self.confidenceMirrorEnabled, !self.isSleeping {
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
        DistributedNotificationCenter.default().addObserver(forName: Self.reopenNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.openSettings() }
        }
    }

    /// A second copy (for example, one still inside the DMG) would publish duplicate
    /// NDI names and fight over the receiver. Hand off to the running copy instead.
    private func handOffToRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains(where: { $0.processIdentifier != current && !$0.isTerminated }) else { return false }
        logger.notice("Another Sanctuary NDI is already running; asking it to open Settings and quitting")
        DistributedNotificationCenter.default().postNotificationName(Self.reopenNotification, object: nil, deliverImmediately: true)
        NSApp.terminate(nil)
        return true
    }

    func launch() async {
        guard !didLaunch else { return }
        didLaunch = true
        guard !handOffToRunningInstance() else { return }
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
        // Enumeration can be empty while the Mac's displays wake up.
        availabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.refreshScreenPermission()
                guard !self.isSleeping, self.screenPermissionGranted else { continue }
                if self.displayManager.displays.isEmpty ||
                    [self.projectorBroadcast, self.userBroadcast].contains(where: { $0.status == .displayMissing || $0.status == .permissionRequired }) {
                    await self.displayManager.refresh()
                }
            }
        }
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
        await displayManager.refresh()
        configureBroadcasts(force: true)
        await projectorBroadcast.waitUntilSettled()
        await userBroadcast.waitUntilSettled()
        updateBroadcastStatus()
    }

    func settingsChanged(recreateSender: Bool = false) {
        configureBroadcasts()
    }

    func recheckAvailability() async {
        guard !availabilityIsRechecking else { return }
        availabilityIsRechecking = true
        wizardError = nil
        defer { availabilityIsRechecking = false }
        refreshProPresenterState()
        await displayManager.refresh()
        configureBroadcasts()
        await projectorBroadcast.waitUntilSettled()
        await userBroadcast.waitUntilSettled()
        updateBroadcastStatus()
    }

    func beginWizard(mode: ProjectorInputMode, mirrorToConfidenceDisplay: Bool) {
        guard !wizardIsWorking else { return }
        wizardTask = Task { [weak self] in
            await self?.completeWizard(mode: mode, mirrorToConfidenceDisplay: mirrorToConfidenceDisplay)
        }
    }

    func cancelWizardConnection() { wizardTask?.cancel() }

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
            if receiverIsBusy {
                wizardMessage = "Waiting for the receiver test to finish…"
                await receiverTask?.value
            }
            wizardMessage = "Checking available screens and feeds…"
            await displayManager.refresh()
            try Task.checkCancellation()
            switch mode {
            case .proPresenter:
                let justOpened = try await ensureProPresenterRunning()
                if preferences.magewellEnabled {
                    wizardMessage = "Connecting the projector to ProPresenter…"
                    // A freshly opened ProPresenter needs extra time before its NDI output is discoverable.
                    _ = try await selectReceiverSourceWithRetry(matching: preferences.proPresenterSourceMatch,
                                                                attempts: justOpened ? 30 : 15)
                }
                try Task.checkCancellation()
                // Only drop the duplicate once the projector has actually been switched away from it.
                confidenceMirrorEnabled = false
                confidenceMirror.hide()
                activeMode = .proPresenter
            case .screenMirror:
                refreshScreenPermission()
                guard screenPermissionGranted else {
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
                try await AvailabilityRetry.run(attempts: 5, operation: {
                    self.configureBroadcasts()
                    await self.projectorBroadcast.waitUntilSettled()
                    try Task.checkCancellation()
                    guard self.projectorBroadcast.status == .broadcasting else {
                        throw StartupWorkflowError.broadcastFailed(self.projectorBroadcast.detail)
                    }
                }, shouldRetry: { error in
                    if case StartupWorkflowError.broadcastFailed = error { return true }
                    return false
                }, onRetry: { attempt in
                    self.wizardMessage = "Waiting for the monitor feed… Rechecking (\(attempt)/5)."
                })
                if preferences.magewellEnabled {
                    wizardMessage = "Connecting the projector to the monitor feed…"
                    _ = try await selectReceiverSourceWithRetry(matching: preferences.screenMirrorSourceMatch)
                }
                try Task.checkCancellation()
                activeMode = .screenMirror
            }
            preferences.lastMode = mode
            if mode == .screenMirror { preferences.lastMirrorToConfidence = mirrorToConfidenceDisplay }
            logger.info("Startup wizard completed: \(mode.rawValue, privacy: .public), confidence \(self.confidenceMirrorEnabled)")
            updateBroadcastStatus()
            wizardMessage = "Ready"
            wizardWindowController?.finish()
            wizardWindowController = nil
            updateActivationPolicy()
        } catch is CancellationError {
            wizardError = "Connection check stopped. Choose Recheck & Retry when you are ready."
        } catch {
            logger.error("Startup wizard failed: \(error.localizedDescription, privacy: .public)")
            wizardError = error.localizedDescription
        }
    }

    /// Returns true when ProPresenter had to be opened during this call.
    private func ensureProPresenterRunning() async throws -> Bool {
        refreshProPresenterState()
        guard !proPresenterRunning else { return false }
        wizardMessage = "Opening ProPresenter…"
        guard launchProPresenter() else { throw StartupWorkflowError.proPresenterNotInstalled }
        for second in 1...90 {
            try await Task.sleep(for: .seconds(1))
            refreshProPresenterState()
            if proPresenterRunning { return true }
            wizardMessage = "Opening ProPresenter… (\(second)s)"
        }
        throw StartupWorkflowError.proPresenterNotRunning
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

    private func selectReceiverSourceWithRetry(matching name: String, attempts: Int = 15) async throws -> MagewellSource {
        try await AvailabilityRetry.run(attempts: attempts, operation: {
            try await self.magewell.selectSource(
                    matching: name,
                    address: self.preferences.magewellAddress,
                    username: self.preferences.magewellUsername,
                    password: self.magewellPassword
                )
        }, shouldRetry: AvailabilityRetry.receiverMayBecomeAvailable, onRetry: { attempt in
            self.wizardMessage = "Waiting for the projector receiver or NDI source… Rechecking (\(attempt)/\(attempts))."
        })
    }

    var receiverActionsAvailable: Bool { !receiverIsBusy && !wizardIsWorking }

    func testMagewellConnection() {
        guard receiverActionsAvailable else { return }
        receiverIsBusy = true
        receiverTestMessage = "Testing…"
        receiverTask = Task {
            defer { receiverIsBusy = false }
            do {
                let sources = try await magewell.sources(
                    address: preferences.magewellAddress,
                    username: preferences.magewellUsername,
                    password: magewellPassword
                )
                guard !Task.isCancelled else { return }
                discoveredSources = sources.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                receiverTestMessage = "Connected — \(sources.count) NDI source\(sources.count == 1 ? "" : "s") found."
            } catch {
                discoveredSources = []
                receiverTestMessage = error.localizedDescription
            }
        }
    }

    /// Routes the receiver immediately, without the wizard. Intended for troubleshooting.
    func switchProjector(to mode: ProjectorInputMode) {
        guard receiverActionsAvailable else { return }
        receiverIsBusy = true
        receiverTestMessage = "Switching the projector to \(title(for: mode))…"
        receiverTask = Task {
            defer { receiverIsBusy = false }
            do {
                let match = mode == .proPresenter ? preferences.proPresenterSourceMatch : preferences.screenMirrorSourceMatch
                let source = try await magewell.selectSource(
                    matching: match,
                    address: preferences.magewellAddress,
                    username: preferences.magewellUsername,
                    password: magewellPassword
                )
                try Task.checkCancellation()
                if mode == .proPresenter {
                    confidenceMirrorEnabled = false
                    confidenceMirror.hide()
                }
                activeMode = mode
                updateBroadcastStatus()
                logger.info("Projector manually switched to \(source.name, privacy: .public)")
                receiverTestMessage = "Projector switched to “\(source.name)”."
            } catch {
                receiverTestMessage = error.localizedDescription
            }
        }
    }

    func matchSummary(for mode: ProjectorInputMode) -> String? {
        guard !discoveredSources.isEmpty else { return nil }
        let match = mode == .proPresenter ? preferences.proPresenterSourceMatch : preferences.screenMirrorSourceMatch
        return MagewellClient.matchSummary(match, in: discoveredSources)
    }

    func title(for mode: ProjectorInputMode) -> String {
        mode == .screenMirror ? preferences.inputDisplayTitle : mode.title
    }

    /// Returns a message for the user when the name cannot be used.
    func renameProjectorSource(_ name: String) -> String? {
        do {
            try preferences.renameProjectorSource(to: name)
            configureBroadcasts()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func saveMagewellPassword(_ password: String) {
        magewellPassword = password
        do { try KeychainStore.setPassword(password) }
        catch { receiverTestMessage = "Could not save password: \(error.localizedDescription)" }
    }

    /// Polled while the wizard is visible; publishes only real changes to avoid redrawing every second.
    func refreshEnvironmentState() {
        refreshProPresenterState()
        refreshScreenPermission()
    }

    func refreshProPresenterState() {
        let running = NSWorkspace.shared.runningApplications.contains {
            !$0.isTerminated && (
                $0.bundleIdentifier?.localizedCaseInsensitiveContains("renewedvision.ProPresenter") == true ||
                $0.localizedName?.localizedCaseInsensitiveContains("ProPresenter") == true
            )
        }
        if running != proPresenterRunning { proPresenterRunning = running }
    }

    private func refreshScreenPermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != screenPermissionGranted { screenPermissionGranted = granted }
    }

    var proPresenterInstalled: Bool { proPresenterURL != nil }

    private var proPresenterURL: URL? {
        let bundleIdentifiers = [
            "com.renewedvision.ProPresenter",
            "com.renewedvision.ProPresenter7",
            "com.renewedvision.ProPresenter6"
        ]
        let paths = ["/Applications/ProPresenter.app", "/Applications/ProPresenter 7.app"]
        return bundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            ?? paths.first(where: FileManager.default.fileExists(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    private func launchProPresenter() -> Bool {
        guard let url = proPresenterURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    func openProPresenter() {
        if !launchProPresenter() { wizardError = StartupWorkflowError.proPresenterNotInstalled.localizedDescription }
        refreshProPresenterState()
    }

    func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
        refreshScreenPermission()
        Task { await displayManager.refresh() }
    }

    /// Labels every physical screen with its role so the right monitors can be chosen.
    func identifyScreens() {
        Task {
            await displayManager.refresh()
            screenIdentifier.show(displays: displayManager.displays) { [weak self] display in
                self?.roles(for: display) ?? []
            }
        }
    }

    func resolvedDisplay(_ identity: DisplayIdentity?) -> DisplayDescriptor? {
        identity.flatMap { DisplayIdentity.bestMatch(for: $0, in: displayManager.displays) }
    }

    func roles(for display: DisplayDescriptor) -> [String] {
        var roles: [String] = []
        let displays = displayManager.displays
        func matches(_ identity: DisplayIdentity?) -> Bool {
            identity.flatMap { DisplayIdentity.bestMatch(for: $0, in: displays) }?.id == display.id
        }
        if matches(preferences.selectedDisplay) { roles.append("\(preferences.inputDisplayTitle) (projector feed)") }
        if matches(preferences.userDisplay) { roles.append("User screen") }
        if matches(preferences.confidenceDisplay) { roles.append("Confidence monitor") }
        return roles
    }

    var confidenceStatus: String {
        guard confidenceMirrorEnabled else { return "Off" }
        guard let id = confidenceMirror.displayID,
              let display = displayManager.displays.first(where: { $0.id == id }) else {
            return "On, but the confidence monitor is not connected"
        }
        return "Mirroring to \(display.displayName)"
    }

    var projectorSummary: String {
        guard let activeMode else { return "Projector: not chosen yet" }
        return "Projector shows: \(title(for: activeMode))"
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openLoginItemsSettings() { LoginItemManager.openSystemSettings() }

    /// Starts a fresh copy once this one has fully exited, e.g. after granting Screen Recording.
    func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                             Bundle.main.bundlePath]
        do {
            try process.run()
            logger.notice("Relaunching Sanctuary NDI")
            NSApp.terminate(nil)
        } catch {
            detail = "Could not relaunch: \(error.localizedDescription)"
        }
    }

    func resetAllSettings() {
        logger.notice("Resetting all settings to defaults")
        wizardTask?.cancel()
        receiverTask?.cancel()
        activeMode = nil
        preferences.resetToDefaults()
        saveMagewellPassword("")
        discoveredSources = []
        receiverTestMessage = "Not tested"
        confidenceMirrorEnabled = false
        confidenceMirror.hide()
        setLaunchAtLogin(preferences.launchAtLogin)
        configureBroadcasts(force: true)
        updateBroadcastStatus()
        openStartupWizard()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        preferences.launchAtLogin = enabled
        do { try LoginItemManager.setEnabled(enabled) }
        catch { detail = "Could not update Launch at Login: \(error.localizedDescription)" }
    }

    func copyDiagnostics() {
        let display = selectedDisplay?.displayName ?? preferences.selectedDisplay?.name ?? "None"
        let identity = selectedDisplay?.identity.uuid ?? preferences.selectedDisplay?.uuid ?? "None"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        let displays = displayManager.displays.map { display in
            let roles = roles(for: display)
            return "  - \(display.displayName) [ID \(display.id)\(display.isMain ? ", main" : "")]: \(roles.isEmpty ? "no role" : roles.joined(separator: ", "))"
        }.joined(separator: "\n")
        let sources = discoveredSources.isEmpty ? "  (run Save Password & Test to list)" : discoveredSources.map { "  - \($0.name)" }.joined(separator: "\n")
        let text = """
        Sanctuary NDI \(version) (\(build))
        App location: \(Bundle.main.bundlePath)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(SystemInfo.architecture)
        Status: \(status.rawValue)
        Selected display: \(display)
        Display UUID: \(identity)
        Resolution: \(Int(frameSize.width))×\(Int(frameSize.height))
        Frame rate: \(preferences.frameRate)
        Show mouse pointer: \(preferences.showsCursor ? "yes" : "no")
        NDI source: \(preferences.sourceName)
        NDI runtime: \(NDISender.runtimeVersion)
        Projector NDI receivers: \(projectorBroadcast.sender.connections)
        Projector feed: \(projectorBroadcast.status.rawValue) — \(projectorBroadcast.detail)
        User display: \(preferences.userDisplay?.name ?? "Not selected")
        User NDI source: \(preferences.userSourceName)
        User NDI receivers: \(userBroadcast.sender.connections)
        User feed: \(userBroadcast.status.rawValue) — \(userBroadcast.detail)
        Connected displays:
        \(displays.isEmpty ? "  (none visible)" : displays)
        Operating mode: \(activeMode?.title ?? "Startup wizard")
        Last wizard choice: \(preferences.lastMode?.title ?? "None")
        Confidence mirror: \(confidenceStatus)
        Confidence display: \(preferences.confidenceDisplay?.name ?? "Not selected")
        ProPresenter: \(proPresenterRunning ? "running" : (proPresenterInstalled ? "installed, not running" : "not found"))
        Projector control: \(preferences.magewellEnabled ? "enabled" : "disabled")
        Projector receiver: \(preferences.magewellAddress.isEmpty ? "not configured" : preferences.magewellAddress)
        Receiver username: \(preferences.magewellUsername.isEmpty ? "not set" : "set")
        Receiver password: \(magewellPassword.isEmpty ? "not saved" : "saved in Keychain")
        ProPresenter source match: \(preferences.proPresenterSourceMatch)
        Monitor source match: \(preferences.screenMirrorSourceMatch)
        Last receiver result: \(receiverTestMessage)
        Receiver sources:
        \(sources)
        Screen recording permission: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")
        Launch at Login: \(LoginItemManager.statusDescription)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyRecentLog() async {
        let log = await RecentLog.text(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log, forType: .string)
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
    case proPresenterNotInstalled
    case screenPermissionRequired
    case inputDisplayMissing
    case confidenceDisplayMissing
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .proPresenterNotRunning: "ProPresenter did not finish opening. Open it, then choose Recheck & Retry."
        case .proPresenterNotInstalled: "ProPresenter was not found in the Applications folder. Open it manually, then try again."
        case .screenPermissionRequired: "Allow Screen Recording in System Settings, then return and try again."
        case .inputDisplayMissing: "Choose which connected monitor is the input monitor before continuing."
        case .confidenceDisplayMissing: "Choose a connected confidence monitor, or choose Projector only."
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
