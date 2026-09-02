import AppKit
import Combine
import CoreGraphics
import OSLog
import ScreenCaptureKit

nonisolated private func displayReconfigurationCallback(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in await manager.refresh() }
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayDescriptor] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Display")
    var onDisplaysChanged: (() -> Void)?

    init() {
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque()) }

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
            }.sorted { ($0.isMain ? 0 : 1, $0.displayName) < ($1.isMain ? 0 : 1, $1.displayName) }
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
