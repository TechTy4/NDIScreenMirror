import AppKit
import Combine
import CoreGraphics
import OSLog
import ScreenCaptureKit

nonisolated private func displayReconfigurationCallback(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    // macOS reports a begin and an end event for every display involved in one change.
    guard let context, !flags.contains(.beginConfigurationFlag) else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in manager.scheduleRefresh() }
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayDescriptor] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Display")
    var onDisplaysChanged: (() -> Void)?
    private var pendingRefresh: Task<Void, Never>?

    init() {
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque()) }

    /// Coalesces bursts of reconfiguration events (plugging in, rearranging, waking)
    /// into one enumeration so feeds and the confidence window restart only once.
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let screens = NSScreen.screens
            displays = content.displays.map { display in
                let screen = screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }
                let displayUUID = CGDisplayCreateUUIDFromDisplayID(display.displayID).takeRetainedValue()
                let uuid = CFUUIDCreateString(nil, displayUUID) as String
                let name = screen?.localizedName ?? (CGDisplayIsBuiltin(display.displayID) != 0 ? "Built-in Display" : "External Display")
                let identity = DisplayIdentity(
                    uuid: uuid,
                    vendorID: CGDisplayVendorNumber(display.displayID),
                    modelID: CGDisplayModelNumber(display.displayID),
                    serialNumber: CGDisplaySerialNumber(display.displayID),
                    name: name,
                    nativeWidth: display.width,
                    nativeHeight: display.height
                )
                return DisplayDescriptor(id: display.displayID, identity: identity,
                                         width: display.width, height: display.height,
                                         isMain: CGDisplayIsMain(display.displayID) != 0)
            }
            // Main first, then left-to-right as arranged, so numbers follow the physical layout.
            .sorted { ($0.isMain ? 0 : 1, CGDisplayBounds($0.id).minX, $0.id) < ($1.isMain ? 0 : 1, CGDisplayBounds($1.id).minX, $1.id) }
            .enumerated().map { index, display in
                var display = display
                display.number = index + 1
                return display
            }
            logger.info("Enumerated \(self.displays.count) displays")
            onDisplaysChanged?()
        } catch {
            logger.error("Display enumeration failed: \(error.localizedDescription, privacy: .public)")
            displays = []
            onDisplaysChanged?()
        }
    }

    func screenCaptureDisplay(id: CGDirectDisplayID) async throws -> SCDisplay? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.displays.first { $0.displayID == id }
    }
}
