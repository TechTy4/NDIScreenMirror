import CoreMedia
import CoreVideo
import Foundation
import OSLog
import ScreenCaptureKit

final class CaptureManager: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let outputQueue = DispatchQueue(label: "org.sanctuary.ndi.capture", qos: .userInteractive)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "Capture")
    private var stream: SCStream?
    private var generation = UUID()
    var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?
    var onStopped: (@Sendable (Error) -> Void)?

    func start(display: SCDisplay, frameRate: Int, showsCursor: Bool) async throws {
        await stop()
        generation = UUID()
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.queueDepth = 3
        // BGRA is ScreenCaptureKit's native, universally supported packed format.
        // NDI accepts it directly and performs its optimized internal conversion.
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false
        configuration.scalesToFit = false
        configuration.colorSpaceName = CGColorSpace.itur_709
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        self.stream = stream
        try await stream.startCapture()
        logger.info("Capture started at \(display.width)x\(display.height) / \(frameRate) fps")
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        do { try await stream.stopCapture() } catch { logger.debug("Capture stop: \(error.localizedDescription, privacy: .public)") }
        logger.info("Capture stopped")
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Capture interrupted: \(error.localizedDescription, privacy: .public)")
        onStopped?(error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        onFrame?(pixelBuffer, sampleBuffer.presentationTimeStamp)
    }
}
