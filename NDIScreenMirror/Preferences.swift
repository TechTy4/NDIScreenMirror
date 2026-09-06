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
        static let launchAtLogin = "launchAtLogin"
        static let magewellEnabled = "magewellEnabled"
        static let magewellAddress = "magewellAddress"
        static let magewellUsername = "magewellUsername"
        static let proPresenterSourceMatch = "proPresenterSourceMatch"
        static let screenMirrorSourceMatch = "screenMirrorSourceMatch"
    }

    private let defaults: UserDefaults

    @Published var sourceName: String { didSet { defaults.set(sourceName, forKey: Key.sourceName) } }
    @Published var frameRate: Int { didSet { defaults.set(frameRate, forKey: Key.frameRate) } }
    @Published var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Key.showsCursor) } }
    @Published var selectedDisplay: DisplayIdentity? {
        didSet {
            if let selectedDisplay, let data = try? JSONEncoder().encode(selectedDisplay) {
                defaults.set(data, forKey: Key.selectedDisplay)
            } else { defaults.removeObject(forKey: Key.selectedDisplay) }
        }
    }
    @Published var confidenceDisplay: DisplayIdentity? {
        didSet {
            if let confidenceDisplay, let data = try? JSONEncoder().encode(confidenceDisplay) {
                defaults.set(data, forKey: Key.confidenceDisplay)
            } else { defaults.removeObject(forKey: Key.confidenceDisplay) }
        }
    }
    @Published var userDisplay: DisplayIdentity? {
        didSet {
            if let userDisplay, let data = try? JSONEncoder().encode(userDisplay) {
                defaults.set(data, forKey: Key.userDisplay)
            } else { defaults.removeObject(forKey: Key.userDisplay) }
        }
    }
    let userSourceName = "Sanctuary User Screen"
    @Published var inputDisplayLabel: String { didSet { defaults.set(inputDisplayLabel, forKey: Key.inputDisplayLabel) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var magewellEnabled: Bool { didSet { defaults.set(magewellEnabled, forKey: Key.magewellEnabled) } }
    @Published var magewellAddress: String { didSet { defaults.set(magewellAddress, forKey: Key.magewellAddress) } }
    @Published var magewellUsername: String { didSet { defaults.set(magewellUsername, forKey: Key.magewellUsername) } }
    @Published var proPresenterSourceMatch: String { didSet { defaults.set(proPresenterSourceMatch, forKey: Key.proPresenterSourceMatch) } }
    @Published var screenMirrorSourceMatch: String { didSet { defaults.set(screenMirrorSourceMatch, forKey: Key.screenMirrorSourceMatch) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sourceName = defaults.string(forKey: Key.sourceName) ?? "Sanctuary Projector Screen"
        frameRate = defaults.object(forKey: Key.frameRate) as? Int ?? 60
        showsCursor = defaults.object(forKey: Key.showsCursor) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        let storedInputLabel = defaults.string(forKey: Key.inputDisplayLabel)
        inputDisplayLabel = storedInputLabel == "Left / Projector Monitor"
            ? "Left/Projector Monitor"
            : (storedInputLabel ?? "Left/Projector Monitor")
        if storedInputLabel == "Left / Projector Monitor" {
            defaults.set("Left/Projector Monitor", forKey: Key.inputDisplayLabel)
        }
        magewellEnabled = defaults.object(forKey: Key.magewellEnabled) as? Bool ?? true
        magewellAddress = defaults.string(forKey: Key.magewellAddress) ?? ""
        magewellUsername = defaults.string(forKey: Key.magewellUsername) ?? "Admin"
        proPresenterSourceMatch = defaults.string(forKey: Key.proPresenterSourceMatch) ?? "ProPresenter"
        screenMirrorSourceMatch = defaults.string(forKey: Key.screenMirrorSourceMatch) ?? "Sanctuary Projector Screen"
        if let data = defaults.data(forKey: Key.selectedDisplay) {
            selectedDisplay = try? JSONDecoder().decode(DisplayIdentity.self, from: data)
        } else { selectedDisplay = nil }
        if let data = defaults.data(forKey: Key.userDisplay) {
            userDisplay = try? JSONDecoder().decode(DisplayIdentity.self, from: data)
        } else { userDisplay = nil }
        if let data = defaults.data(forKey: Key.confidenceDisplay) {
            confidenceDisplay = try? JSONDecoder().decode(DisplayIdentity.self, from: data)
        } else { confidenceDisplay = nil }
    }
}
