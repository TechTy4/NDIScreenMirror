import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let sourceName = "sourceName"
        static let frameRate = "frameRate"
        static let showsCursor = "showsCursor"
        static let selectedDisplay = "selectedDisplay"
        static let userDisplay = "userDisplay"
        static let confidenceDisplay = "confidenceDisplay"
        static let inputDisplayLabel = "inputDisplayLabel"
        static let screenConfigurationLabel = "screenConfigurationLabel"
        static let launchAtLogin = "launchAtLogin"
        static let magewellEnabled = "magewellEnabled"
        static let magewellAddress = "magewellAddress"
        static let magewellUsername = "magewellUsername"
        static let proPresenterSourceMatch = "proPresenterSourceMatch"
        static let screenMirrorSourceMatch = "screenMirrorSourceMatch"
        static let lastMode = "lastMode"
        static let lastMirrorToConfidence = "lastMirrorToConfidence"

        static let all = [sourceName, frameRate, showsCursor, selectedDisplay, userDisplay, confidenceDisplay,
                          inputDisplayLabel, screenConfigurationLabel, launchAtLogin, magewellEnabled,
                          magewellAddress, magewellUsername, proPresenterSourceMatch, screenMirrorSourceMatch,
                          lastMode, lastMirrorToConfidence]
    }

    enum Default {
        static let sourceName = "Sanctuary Projector Screen"
        static let userSourceName = "Sanctuary User Screen"
        static let frameRate = 60
        static let showsCursor = true
        static let inputDisplayLabel = "Left/Projector Monitor"
        static let screenConfigurationLabel = "Configure Screens"
        static let launchAtLogin = true
        static let magewellEnabled = true
        static let magewellUsername = "Admin"
        static let proPresenterSourceMatch = "ProPresenter"
    }

    private let defaults: UserDefaults

    @Published var sourceName: String { didSet { defaults.set(sourceName, forKey: Key.sourceName) } }
    @Published var frameRate: Int { didSet { defaults.set(frameRate, forKey: Key.frameRate) } }
    @Published var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Key.showsCursor) } }
    @Published var selectedDisplay: DisplayIdentity? { didSet { store(selectedDisplay, forKey: Key.selectedDisplay) } }
    @Published var confidenceDisplay: DisplayIdentity? { didSet { store(confidenceDisplay, forKey: Key.confidenceDisplay) } }
    @Published var userDisplay: DisplayIdentity? { didSet { store(userDisplay, forKey: Key.userDisplay) } }
    let userSourceName = Default.userSourceName
    @Published var inputDisplayLabel: String { didSet { defaults.set(inputDisplayLabel, forKey: Key.inputDisplayLabel) } }
    @Published var screenConfigurationLabel: String { didSet { defaults.set(screenConfigurationLabel, forKey: Key.screenConfigurationLabel) } }
    var screenConfigurationMenuTitle: String {
        let label = screenConfigurationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? Default.screenConfigurationLabel : label
    }
    var inputDisplayTitle: String {
        let label = inputDisplayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? Default.inputDisplayLabel : label
    }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var magewellEnabled: Bool { didSet { defaults.set(magewellEnabled, forKey: Key.magewellEnabled) } }
    @Published var magewellAddress: String { didSet { defaults.set(magewellAddress, forKey: Key.magewellAddress) } }
    @Published var magewellUsername: String { didSet { defaults.set(magewellUsername, forKey: Key.magewellUsername) } }
    @Published var proPresenterSourceMatch: String { didSet { defaults.set(proPresenterSourceMatch, forKey: Key.proPresenterSourceMatch) } }
    @Published var screenMirrorSourceMatch: String { didSet { defaults.set(screenMirrorSourceMatch, forKey: Key.screenMirrorSourceMatch) } }
    /// The last successfully completed wizard choice, pre-selected at the next launch.
    @Published var lastMode: ProjectorInputMode? { didSet { defaults.set(lastMode?.rawValue, forKey: Key.lastMode) } }
    @Published var lastMirrorToConfidence: Bool { didSet { defaults.set(lastMirrorToConfidence, forKey: Key.lastMirrorToConfidence) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        screenConfigurationLabel = defaults.string(forKey: Key.screenConfigurationLabel) ?? Default.screenConfigurationLabel
        sourceName = defaults.string(forKey: Key.sourceName) ?? Default.sourceName
        frameRate = defaults.object(forKey: Key.frameRate) as? Int ?? Default.frameRate
        showsCursor = defaults.object(forKey: Key.showsCursor) as? Bool ?? Default.showsCursor
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? Default.launchAtLogin
        let storedInputLabel = defaults.string(forKey: Key.inputDisplayLabel)
        inputDisplayLabel = storedInputLabel == "Left / Projector Monitor"
            ? Default.inputDisplayLabel
            : (storedInputLabel ?? Default.inputDisplayLabel)
        if storedInputLabel == "Left / Projector Monitor" {
            defaults.set(Default.inputDisplayLabel, forKey: Key.inputDisplayLabel)
        }
        magewellEnabled = defaults.object(forKey: Key.magewellEnabled) as? Bool ?? Default.magewellEnabled
        magewellAddress = defaults.string(forKey: Key.magewellAddress) ?? ""
        magewellUsername = defaults.string(forKey: Key.magewellUsername) ?? Default.magewellUsername
        proPresenterSourceMatch = defaults.string(forKey: Key.proPresenterSourceMatch) ?? Default.proPresenterSourceMatch
        screenMirrorSourceMatch = defaults.string(forKey: Key.screenMirrorSourceMatch) ?? Default.sourceName
        lastMode = defaults.string(forKey: Key.lastMode).flatMap(ProjectorInputMode.init(rawValue:))
        lastMirrorToConfidence = defaults.object(forKey: Key.lastMirrorToConfidence) as? Bool ?? false
        selectedDisplay = Self.identity(in: defaults, forKey: Key.selectedDisplay)
        userDisplay = Self.identity(in: defaults, forKey: Key.userDisplay)
        confidenceDisplay = Self.identity(in: defaults, forKey: Key.confidenceDisplay)
    }

    /// Renames the projector feed. When the receiver match still targets the old
    /// name, it follows the rename so automatic projector switching keeps working.
    func renameProjectorSource(to proposed: String) throws {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SourceNameError.empty }
        guard name.caseInsensitiveCompare(userSourceName) != .orderedSame else { throw SourceNameError.collidesWithUserFeed }
        guard name != sourceName else { return }
        // Covers both the bare name and a host-qualified one such as "HOST (old name)".
        let match = screenMirrorSourceMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only the parenthesised source component is replaced, never text inside the hostname.
        if match.isEmpty || match.caseInsensitiveCompare(sourceName) == .orderedSame {
            screenMirrorSourceMatch = name
        } else if let range = match.range(of: "(\(sourceName))", options: [.caseInsensitive, .backwards]) {
            screenMirrorSourceMatch = match.replacingCharacters(in: range, with: "(\(name))")
        }
        sourceName = name
    }

    /// Restores every setting to its first-launch value. The Keychain password is separate.
    func resetToDefaults() {
        Key.all.forEach(defaults.removeObject(forKey:))
        sourceName = Default.sourceName
        frameRate = Default.frameRate
        showsCursor = Default.showsCursor
        selectedDisplay = nil
        userDisplay = nil
        confidenceDisplay = nil
        inputDisplayLabel = Default.inputDisplayLabel
        screenConfigurationLabel = Default.screenConfigurationLabel
        launchAtLogin = Default.launchAtLogin
        magewellEnabled = Default.magewellEnabled
        magewellAddress = ""
        magewellUsername = Default.magewellUsername
        proPresenterSourceMatch = Default.proPresenterSourceMatch
        screenMirrorSourceMatch = Default.sourceName
        lastMode = nil
        lastMirrorToConfidence = false
    }

    private func store(_ identity: DisplayIdentity?, forKey key: String) {
        if let identity, let data = try? JSONEncoder().encode(identity) {
            defaults.set(data, forKey: key)
        } else { defaults.removeObject(forKey: key) }
    }

    private static func identity(in defaults: UserDefaults, forKey key: String) -> DisplayIdentity? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DisplayIdentity.self, from: $0) }
    }
}

enum SourceNameError: LocalizedError, Equatable {
    case empty
    case collidesWithUserFeed

    var errorDescription: String? {
        switch self {
        case .empty: "The projector NDI source name cannot be empty."
        case .collidesWithUserFeed: "The projector feed needs a different name from the User feed."
        }
    }
}
