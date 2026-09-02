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
    @Published private(set) var lastFrameAt: Date?

    let preferences = Preferences()
    let displayManager = DisplayManager()
    private let capture = CaptureManager()
    private let sender = NDISender()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Application")
    private var restartTask: Task<Void, Never>?
    private var backoff = RecoveryBackoff()
    private var isSleeping = false
    private var didLaunch = false
    private var processActivity: NSObjectProtocol?
    private var settingsWindowController: SettingsWindowController?

    init() {
        capture.onFrame = { [weak self] buffer, time in
            guard let self else { return }
            self.sender.send(pixelBuffer: buffer, presentationTime: time)
            Task { @MainActor [weak self] in self?.lastFrameAt = Date() }
        }
        capture.onStopped = { [weak self] error in
            Task { @MainActor [weak self] in self?.handleCaptureFailure(error) }
        }
        displayManager.onDisplaysChanged = { [weak self] in Task { @MainActor in await self?.reconcileDisplayAndStart() } }

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
        explainScreenRecordingPermissionIfNeeded()
        await displayManager.refresh()
    }

    private func explainScreenRecordingPermissionIfNeeded() {
        let key = "hasExplainedScreenRecordingPermission"
        guard !CGPreflightScreenCaptureAccess(), !UserDefaults.standard.bool(forKey: key) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = """
        Sanctuary NDI needs Screen Recording permission to mirror the display you choose. macOS will ask for access next. Your screen stays on your local network and is never stored by this app.

        After enabling access in System Settings, macOS may ask you to quit and reopen Sanctuary NDI.
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        UserDefaults.standard.set(true, forKey: key)
        if alert.runModal() == .alertFirstButtonReturn {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func select(_ display: DisplayDescriptor) {
        logger.info("Display selected from menu: \(display.displayName, privacy: .public), ID \(display.id)")
        selectedDisplay = display
        preferences.selectedDisplay = display.identity
        status = .starting
        detail = "Switching to \(display.displayName)…"
        Task { @MainActor [weak self] in
            await self?.restartBroadcast()
        }
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: self) { [weak self] in
                self?.settingsWindowController = nil
            }
        }
        settingsWindowController?.show()
    }

    func restartBroadcast() async {
        restartTask?.cancel()
        await capture.stop()
        sender.stop()
        backoff.reset()
        await reconcileDisplayAndStart()
    }

    func settingsChanged(recreateSender: Bool = false) {
        Task {
            if recreateSender { await restartBroadcast() }
            else { await restartBroadcast() }
        }
    }

    private func reconcileDisplayAndStart() async {
        guard !isSleeping else { return }
        guard CGPreflightScreenCaptureAccess() else {
            status = .permissionRequired
            detail = "Allow Screen Recording to mirror a display."
            return
        }
        guard NDISender.runtimeAvailable else {
            status = .ndiError
            detail = "The bundled NDI runtime is unavailable."
            return
        }
        guard !displayManager.displays.isEmpty else {
            status = .captureError
            detail = "No captureable displays are available."
            return
        }

        let match: DisplayDescriptor?
        if let saved = preferences.selectedDisplay {
            match = DisplayIdentity.bestMatch(for: saved, in: displayManager.displays)
            let savedUUID = saved.uuid ?? "none"
            let resolvedName = match?.displayName ?? "no match"
            logger.info("Resolving saved display \(saved.name, privacy: .public), UUID \(savedUUID, privacy: .public): \(resolvedName, privacy: .public)")
        } else if displayManager.displays.count == 1 {
            match = displayManager.displays[0]
            preferences.selectedDisplay = match?.identity
        } else { match = nil }

        guard let match else {
            selectedDisplay = nil
            status = .displayMissing
            detail = preferences.selectedDisplay == nil ? "Choose a display from Mirror Display." : "The selected display is not connected."
            return
        }
        selectedDisplay = match
        await start(display: match)
    }

    private func start(display: DisplayDescriptor) async {
        status = .starting
        detail = "Starting \(preferences.sourceName)…"
        do {
            guard let scDisplay = try await displayManager.screenCaptureDisplay(id: display.id) else {
                throw BroadcastError.displayDisappeared
            }
            sender.frameRate = preferences.frameRate
            try sender.start(name: preferences.sourceName.trimmingCharacters(in: .whitespacesAndNewlines))
            try await capture.start(display: scDisplay, frameRate: preferences.frameRate, showsCursor: preferences.showsCursor)
            frameSize = CGSize(width: display.width, height: display.height)
            backoff.reset()
            status = .broadcasting
            detail = "NDI: \(preferences.sourceName)"
        } catch {
            sender.stop()
            status = error is NDIError ? .ndiError : .captureError
            detail = "Broadcast stopped. Retrying automatically."
            logger.error("Broadcast start failed: \(error.localizedDescription, privacy: .public)")
            scheduleRetry()
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        guard !isSleeping else { return }
        status = .captureError
        detail = "Screen capture stopped. Retrying automatically."
        sender.stop()
        scheduleRetry()
    }

    private func scheduleRetry() {
        restartTask?.cancel()
        let delay = backoff.nextDelay()
        logger.info("Retrying broadcast in \(delay) seconds")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.displayManager.refresh()
        }
    }

    private func sleep() async {
        isSleeping = true
        restartTask?.cancel()
        status = .sleeping
        detail = "Paused while the Mac sleeps."
        await capture.stop()
        sender.stop()
    }

    private func wake() async {
        isSleeping = false
        try? await Task.sleep(for: .seconds(2))
        await displayManager.refresh()
    }

    func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
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
        NDI receivers: \(sender.connections)
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
            string: "Mirrors one selected display as a High Bandwidth NDI® source.\n\nNDI® is a registered trademark of Vizrt NDI AB.\n",
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
