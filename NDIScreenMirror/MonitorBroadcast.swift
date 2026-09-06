import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// One independently recoverable screen feed. Routing the projector never stops it.
@MainActor
final class MonitorBroadcast: ObservableObject {
    @Published private(set) var status: BroadcastStatus = .starting
    @Published private(set) var detail = "Preparing…"
    @Published private(set) var display: DisplayDescriptor?
    let capture = CaptureManager()
    let sender = NDISender()

    private struct Configuration: Equatable {
        let display: DisplayDescriptor?
        let name: String
        let frameRate: Int
        let cursor: Bool
        let sleeping: Bool
    }
    private var desired: Configuration?
    private var running: Configuration?
    private var worker: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var backoff = RecoveryBackoff()
    private var revision = 0

    init() {
        let sender = self.sender
        capture.onFrame = { buffer, time in sender.send(pixelBuffer: buffer, presentationTime: time) }
        capture.onStopped = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.desired?.sleeping == false else { return }
                self.running = nil
                self.sender.stop()
                self.status = .captureError
                self.detail = "Capture interrupted. Retrying…"
                self.scheduleRetry()
            }
        }
    }

    func configure(display: DisplayDescriptor?, name: String, frameRate: Int, cursor: Bool, sleeping: Bool, force: Bool = false) {
        let next = Configuration(display: display, name: name, frameRate: frameRate, cursor: cursor, sleeping: sleeping)
        guard force || desired != next || running == nil else { return }
        desired = next
        revision += 1
        retry?.cancel()
        if force { running = nil }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while let configuration = self.desired {
                let currentRevision = self.revision
                await self.apply(configuration)
                if currentRevision == self.revision { break }
            }
            self.worker = nil
        }
    }

    func waitUntilSettled() async { await worker?.value }

    private func apply(_ configuration: Configuration) async {
        if running == configuration { return }
        await capture.stop()
        sender.stop()
        running = nil
        display = configuration.display
        if configuration.sleeping {
            status = .sleeping; detail = "Paused while the Mac sleeps."; return
        }
        guard CGPreflightScreenCaptureAccess() else {
            status = .permissionRequired; detail = "Allow Screen Recording in Settings."; scheduleRetry(); return
        }
        guard let display = configuration.display else {
            status = .displayMissing; detail = "Choose a connected monitor in Settings."; return
        }
        status = .starting
        detail = "Starting \(configuration.name)…"
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let screen = content.displays.first(where: { $0.displayID == display.id }) else {
                throw BroadcastError.displayDisappeared
            }
            sender.frameRate = configuration.frameRate
            try sender.start(name: configuration.name)
            try await capture.start(display: screen, frameRate: configuration.frameRate, showsCursor: configuration.cursor)
            running = configuration
            backoff.reset()
            status = .broadcasting
            detail = configuration.name
        } catch {
            await capture.stop()
            sender.stop()
            status = error is NDIError ? .ndiError : .captureError
            detail = "\(error.localizedDescription) Retrying…"
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retry?.cancel()
        let delay = backoff.nextDelay()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let configuration = self.desired else { return }
            self.configure(display: configuration.display, name: configuration.name, frameRate: configuration.frameRate,
                           cursor: configuration.cursor, sleeping: configuration.sleeping, force: true)
        }
    }
}
