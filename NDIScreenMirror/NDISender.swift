import CoreVideo
import CoreMedia
import Foundation
import OSLog

final class NDISender: @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SanctuaryNDI", category: "NDI")
    private let lock = NSLock()
    private var sender: OpaquePointer?
    var frameRate = 60

    static var runtimeVersion: String { String(cString: SNDIRuntimeVersion()) }
    static var runtimeAvailable: Bool { SNDIRuntimeIsAvailable() }

    func start(name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        stopUnlocked()
        var error = [CChar](repeating: 0, count: 512)
        sender = name.withCString { SNDISenderCreate($0, &error, Int32(error.count)) }
        guard sender != nil else { throw NDIError.creation(String(cString: error)) }
        logger.info("NDI sender created: \(name, privacy: .public)")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopUnlocked()
    }

    private func stopUnlocked() {
        if let sender { SNDISenderDestroy(sender); self.sender = nil; logger.info("NDI sender destroyed") }
    }

    func send(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard let sender else { return }
        let timecode = presentationTime.isNumeric ? Int64(presentationTime.seconds * 10_000_000) : Int64.max
        _ = SNDISenderSendPixelBuffer(sender, pixelBuffer, Int32(frameRate), 1, timecode)
    }

    var connections: Int {
        lock.lock()
        defer { lock.unlock() }
        return sender.map { Int(SNDISenderConnectionCount($0)) } ?? 0
    }
    deinit { stop() }
}

enum NDIError: LocalizedError {
    case creation(String)
    var errorDescription: String? {
        switch self { case .creation(let message): message }
    }
}
