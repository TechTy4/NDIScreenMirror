import Foundation

enum AvailabilityRetry {
    static func run<Value>(
        attempts: Int = 15,
        operation: () async throws -> Value,
        shouldRetry: (Error) -> Bool,
        onRetry: (Int) -> Void = { _ in },
        pause: () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }
    ) async throws -> Value {
        precondition(attempts > 0)
        for attempt in 1...attempts {
            try Task.checkCancellation()
            do { return try await operation() }
            catch {
                guard attempt < attempts, shouldRetry(error) else { throw error }
                onRetry(attempt)
                try await pause()
            }
        }
        fatalError("Retry loop must return or throw")
    }

    static func receiverMayBecomeAvailable(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                    .networkConnectionLost, .notConnectedToInternet, .resourceUnavailable].contains(error.code)
        }
        guard let error = error as? MagewellError else { return false }
        switch error {
        case .sourceNotFound: return true
        case .httpStatus(let code): return code == 408 || code == 429 || (500...599).contains(code)
        default: return false
        }
    }
}
