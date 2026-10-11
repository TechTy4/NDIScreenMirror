import CoreMedia
import CoreVideo
import Foundation
import OSLog
import ScreenCaptureKit

final class CaptureManager: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let outputQueue = DispatchQueue(label: "org.sanctuary.ndi.capture", qos: .userInteractive)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Capture")
    private var stream: SCStream?
    private let stateLock = NSLock()
    private var region: CaptureRegion?
    private var receivedFrame = false
    var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?
    var onSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    var onStopped: (@Sendable (Error) -> Void)?

    func start(display: SCDisplay, frameRate: Int, showsCursor: Bool) async throws {
        await stop()
        let bounds = CGDisplayBounds(display.displayID)
        guard bounds.width > 0, bounds.height > 0 else { throw CaptureError.displayUnavailable }
        let region = CaptureRegion(displayBounds: bounds)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        if #available(macOS 15.2, *) {
            guard filter.includedDisplays.count == 1,
                  filter.includedDisplays.first?.displayID == display.displayID else {
                throw CaptureError.unexpectedDisplayFilter
            }
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = region.width
        configuration.height = region.height
        configuration.destinationRect = CGRect(x: 0, y: 0, width: region.width, height: region.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.queueDepth = 3
        // BGRA is ScreenCaptureKit's native, universally supported packed format.
        // NDI accepts it directly and performs its optimized internal conversion.
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false
        configuration.scalesToFit = false
        configuration.colorSpaceName = CGColorSpace.itur_709
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        stateLock.withLock {
            self.stream = stream
            self.region = region
            receivedFrame = false
        }
        try await stream.startCapture()
        logger.info("Single-display capture: ID \(display.displayID), \(region.width)x\(region.height) / \(frameRate) fps")
    }

    func waitForFirstFrame() async throws {
        for _ in 0..<80 {
            try Task.checkCancellation()
            if stateLock.withLock({ receivedFrame }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CaptureError.noVideoYet
    }

    func stop() async {
        let previous = stateLock.withLock {
            let previous = stream
            stream = nil
            region = nil
            receivedFrame = false
            return previous
        }
        guard let stream = previous else { return }
        do { try await stream.stopCapture() } catch { logger.debug("Capture stop: \(error.localizedDescription, privacy: .public)") }
        logger.info("Capture stopped")
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Capture interrupted: \(error.localizedDescription, privacy: .public)")
        stateLock.withLock {
            guard self.stream === stream else { return }
            onStopped?(error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        stateLock.withLock {
            guard self.stream === stream, let region,
                  CVPixelBufferGetWidth(pixelBuffer) == region.width,
                  CVPixelBufferGetHeight(pixelBuffer) == region.height else { return }
            onFrame?(pixelBuffer, sampleBuffer.presentationTimeStamp)
            receivedFrame = true
            onSampleBuffer?(sampleBuffer)
        }
    }
}

enum CaptureError: LocalizedError {
    case displayUnavailable
    case unexpectedDisplayFilter
    case noVideoYet

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected monitor is not available yet."
        case .unexpectedDisplayFilter: "Capture must contain only the selected monitor."
        case .noVideoYet: "The screen feed has not produced video yet."
        }
    }
}
