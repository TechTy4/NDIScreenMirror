import Foundation
import OSLog

/// Reads this process's own unified-log entries so support can see what happened
/// without opening Console. Entries never contain passwords or frame contents.
enum RecentLog {
    static func text(subsystem: String, limit: Int = 400) async -> String {
        await Task.detached(priority: .utility) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let start = store.position(date: Date().addingTimeInterval(-6 * 60 * 60))
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
                let lines = try store.getEntries(at: start)
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem == subsystem }
                    .suffix(limit)
                    .map { "\(formatter.string(from: $0.date)) [\($0.category)] \(level($0.level)) \($0.composedMessage)" }
                return lines.isEmpty ? "No log entries recorded since launch." : lines.joined(separator: "\n")
            } catch {
                return "Could not read the log: \(error.localizedDescription)"
            }
        }.value
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .error, .fault: "ERROR"
        case .notice: "NOTICE"
        case .debug: "DEBUG"
        default: "INFO"
        }
    }
}
