import CoreGraphics
import Foundation

enum BroadcastStatus: String, Codable, Sendable {
    case starting = "Starting"
    case broadcasting = "Broadcasting"
    case permissionRequired = "Screen Permission Required"
    case displayMissing = "Selected Display Missing"
    case ndiError = "NDI Error"
    case captureError = "Capture Error"
    case sleeping = "Sleeping"

    var symbolName: String {
        switch self {
        case .broadcasting: "dot.radiowaves.left.and.right"
        case .starting: "hourglass"
        case .sleeping: "moon.zzz"
        case .permissionRequired: "lock.shield"
        case .displayMissing: "display"
        case .ndiError, .captureError: "exclamationmark.triangle"
        }
    }
}

struct DisplayIdentity: Codable, Equatable, Hashable, Sendable {
    let uuid: String?
    let vendorID: UInt32
    let modelID: UInt32
    let serialNumber: UInt32
    let name: String
    let nativeWidth: Int
    let nativeHeight: Int

    func matchScore(against candidate: DisplayIdentity) -> Int {
        if let uuid, let other = candidate.uuid, uuid == other { return 10_000 }
        var score = 0
        if vendorID != 0, vendorID == candidate.vendorID { score += 600 }
        if modelID != 0, modelID == candidate.modelID { score += 700 }
        if serialNumber != 0, serialNumber == candidate.serialNumber { score += 2_000 }
        if name.caseInsensitiveCompare(candidate.name) == .orderedSame { score += 250 }
        if nativeWidth == candidate.nativeWidth, nativeHeight == candidate.nativeHeight { score += 100 }
        return score
    }

    static func bestMatch(for saved: DisplayIdentity, in candidates: [DisplayDescriptor]) -> DisplayDescriptor? {
        let ranked = candidates.map { ($0, saved.matchScore(against: $0.identity)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= 1_000 else { return nil }
        if ranked.count > 1, ranked[1].1 == best.1, best.1 < 10_000 { return nil }
        return best.0
    }
}

struct DisplayDescriptor: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let identity: DisplayIdentity
    let width: Int
    let height: Int
    let isMain: Bool

    var displayName: String {
        let suffix = "\(width)×\(height)"
        return identity.name.isEmpty ? "Display — \(suffix)" : "\(identity.name) — \(suffix)"
    }
}

struct RecoveryBackoff: Equatable, Sendable {
    private(set) var attempt = 0
    let maximum: TimeInterval

    init(maximum: TimeInterval = 60) { self.maximum = maximum }

    mutating func nextDelay() -> TimeInterval {
        defer { attempt += 1 }
        return min(maximum, pow(2, Double(attempt)))
    }

    mutating func reset() { attempt = 0 }
}
