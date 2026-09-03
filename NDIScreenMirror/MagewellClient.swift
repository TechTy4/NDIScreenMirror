import CryptoKit
import Foundation

actor MagewellClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    func sources(address: String, username: String, password: String) async throws -> [MagewellSource] {
        let baseURL = try Self.baseURL(from: address)
        do {
            try await loginModern(baseURL: baseURL, username: username, password: password)
            return try await modernSources(baseURL: baseURL)
        } catch where Self.shouldTryLegacy(error) {
            try await loginLegacy(baseURL: baseURL, username: username, password: password)
            return try await legacySources(baseURL: baseURL)
        }
    }

    func selectSource(matching requestedName: String, address: String, username: String, password: String) async throws -> MagewellSource {
        let baseURL = try Self.baseURL(from: address)
        do {
            try await loginModern(baseURL: baseURL, username: username, password: password)
            let sources = try await modernSources(baseURL: baseURL)
            let source = try Self.bestMatch(requestedName, in: sources)
            guard let id = source.id else { throw MagewellError.invalidResponse }
            try await postJSON(baseURL.appending(path: "api/source/select"), body: ["id": id])
            return source
        } catch where Self.shouldTryLegacy(error) {
            try await loginLegacy(baseURL: baseURL, username: username, password: password)
            let sources = try await legacySources(baseURL: baseURL)
            let source = try Self.bestMatch(requestedName, in: sources)
            var components = URLComponents(url: baseURL.appending(path: "mwapi"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "method", value: "set-channel"),
                URLQueryItem(name: "ndi-name", value: "true"),
                URLQueryItem(name: "name", value: source.name)
            ]
            try await requireSuccess(components.url!)
            return source
        }
    }

    private func loginModern(baseURL: URL, username: String, password: String) async throws {
        let data = Data(password.utf8)
        let digests = [
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        ]
        for (index, digest) in digests.enumerated() {
            do {
                try await postJSON(baseURL.appending(path: "api/user/login"), body: ["username": username, "password": digest])
                return
            } catch MagewellError.authenticationFailed where index < digests.count - 1 {
                continue
            } catch MagewellError.httpStatus(let code) where code == 404 || code == 405 {
                throw MagewellError.unsupportedAPI
            } catch MagewellError.invalidResponse {
                throw MagewellError.unsupportedAPI
            }
        }
        throw MagewellError.authenticationFailed
    }

    private func loginLegacy(baseURL: URL, username: String, password: String) async throws {
        let digest = Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
        var components = URLComponents(url: baseURL.appending(path: "mwapi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "method", value: "login"),
            URLQueryItem(name: "id", value: username),
            URLQueryItem(name: "pass", value: digest)
        ]
        try await requireSuccess(components.url!)
    }

    private func modernSources(baseURL: URL) async throws -> [MagewellSource] {
        var components = URLComponents(url: baseURL.appending(path: "api/source/list"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "type", value: "ndi")]
        let object = try await jsonObject(components.url!)
        try Self.checkStatus(object)
        return try Self.parseModernSources(object)
    }

    nonisolated static func parseModernSources(_ object: [String: Any]) throws -> [MagewellSource] {
        try checkStatus(object)
        let dictionaries = (object["list"] ?? object["data"] ?? object["ndi"]) as? [[String: Any]] ?? []
        return dictionaries.compactMap { item in
            guard let name = sourceName(in: item) else { return nil }
            let address = sourceAddress(in: item)
            return MagewellSource(id: item["id"] as? Int, name: name, address: address)
        }
    }

    private func legacySources(baseURL: URL) async throws -> [MagewellSource] {
        var components = URLComponents(url: baseURL.appending(path: "mwapi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "method", value: "get-ndi-sources")]
        let object = try await jsonObject(components.url!)
        try Self.checkStatus(object)
        let dictionaries = object["sources"] as? [[String: Any]] ?? []
        return dictionaries.compactMap { item in
            guard let name = item["ndi-name"] as? String else { return nil }
            return MagewellSource(id: nil, name: name, address: item["ip-addr"] as? String)
        }
    }

    private func postJSON(_ url: URL, body: [String: Any]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MagewellError.invalidResponse
        }
        try Self.checkStatus(object)
    }

    private func requireSuccess(_ url: URL) async throws {
        let object = try await jsonObject(url)
        try Self.checkStatus(object)
    }

    private func jsonObject(_ url: URL) async throws -> [String: Any] {
        let (data, response) = try await session.data(from: url)
        try Self.checkHTTP(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MagewellError.invalidResponse
        }
        return object
    }

    private static func checkHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw MagewellError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw MagewellError.httpStatus(response.statusCode) }
    }

    private static func checkStatus(_ object: [String: Any]) throws {
        let status = object["status"] as? Int ?? object["result"] as? Int
        guard let status else { throw MagewellError.invalidResponse }
        guard status == 0 else {
            if status == 36 { throw MagewellError.authenticationFailed }
            throw MagewellError.deviceStatus(status, object["code"] as? String ?? object["message"] as? String)
        }
    }

    private static func baseURL(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MagewellError.notConfigured }
        let string = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else { throw MagewellError.invalidAddress }
        guard isLocalAddress(host) else { throw MagewellError.invalidAddress }
        return url
    }

    private nonisolated static func isLocalAddress(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".local") || !normalized.contains(".") { return true }
        let parts = normalized.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || parts[0] == 127 ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 169 && parts[1] == 254)
    }

    nonisolated static func bestMatch(_ requestedName: String, in sources: [MagewellSource]) throws -> MagewellSource {
        let needle = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { throw MagewellError.sourceNameMissing }
        if let exact = sources.first(where: { $0.name.caseInsensitiveCompare(needle) == .orderedSame }) { return exact }
        let matches = sources.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        guard matches.count == 1, let match = matches.first else {
            throw MagewellError.sourceNotFound(needle, sources.map(\.name))
        }
        return match
    }

    private nonisolated static func sourceName(in item: [String: Any]) -> String? {
        if let value = item["ndi-name"] as? String, !value.isEmpty { return value }
        guard let config = item["config"] as? [String: Any] else { return item["name"] as? String }
        if let ndi = config["ndi"] as? [String: Any], let value = ndi["name"] as? String, !value.isEmpty { return value }
        if let data = config["data"] as? [String: Any], let value = data["name"] as? String, !value.isEmpty { return value }
        return config["name"] as? String
    }

    private nonisolated static func sourceAddress(in item: [String: Any]) -> String? {
        if let value = item["ip-addr"] as? String { return value }
        guard let config = item["config"] as? [String: Any] else { return item["url"] as? String }
        if let ndi = config["ndi"] as? [String: Any], let value = ndi["url"] as? String { return value }
        if let data = config["data"] as? [String: Any], let value = data["url"] as? String { return value }
        return config["url"] as? String
    }

    private nonisolated static func shouldTryLegacy(_ error: Error) -> Bool {
        guard let error = error as? MagewellError else { return false }
        switch error {
        case .unsupportedAPI, .invalidResponse, .httpStatus(404), .httpStatus(405): return true
        default: return false
        }
    }
}

enum MagewellError: LocalizedError, Equatable {
    case notConfigured
    case invalidAddress
    case authenticationFailed
    case unsupportedAPI
    case invalidResponse
    case httpStatus(Int)
    case deviceStatus(Int, String?)
    case sourceNameMissing
    case sourceNotFound(String, [String])

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Enter the projector receiver address in Settings."
        case .invalidAddress: return "The projector receiver address is not valid."
        case .authenticationFailed: return "The projector receiver rejected the username or password."
        case .unsupportedAPI: return "This projector receiver API is not supported."
        case .invalidResponse: return "The projector receiver returned an unexpected response."
        case .httpStatus(let code): return "The projector receiver returned HTTP \(code)."
        case .deviceStatus(let code, let message): return "Projector receiver error \(code)\(message.map { ": \($0)" } ?? "")."
        case .sourceNameMissing: return "Enter an NDI source name in Settings."
        case .sourceNotFound(let name, let available):
            let suffix = available.isEmpty ? "No NDI sources are currently visible." : "Available: \(available.joined(separator: ", "))."
            return "Could not find an NDI source matching “\(name)”. \(suffix)"
        }
    }
}
