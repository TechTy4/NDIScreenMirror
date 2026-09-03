import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia

final class ConfidenceMirrorController: @unchecked Sendable {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let renderQueue = DispatchQueue(label: "org.sanctuary.ndi.confidence-display", qos: .userInteractive)
    private var window: NSWindow?
    private var isDisplaying = false

    @MainActor
    func show(on display: DisplayDescriptor) throws {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
        }) else { throw ConfidenceMirrorError.displayUnavailable }

        hide()
        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.frame = view.bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(displayLayer)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = view
        window.backgroundColor = .black
        window.level = .normal
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        renderQueue.async { [weak self] in self?.isDisplaying = true }
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
        window = nil
        renderQueue.async { [weak self] in
            self?.isDisplaying = false
            self?.displayLayer.flushAndRemoveImage()
        }
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        renderQueue.async { [weak self] in
            guard let self, isDisplaying, displayLayer.isReadyForMoreMediaData else { return }
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sampleBuffer)
        }
    }
}

enum ConfidenceMirrorError: LocalizedError {
    case displayUnavailable
    case sameDisplay

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected confidence monitor is not connected."
        case .sameDisplay: "Choose a different confidence monitor from the input monitor."
        }
    }
}
