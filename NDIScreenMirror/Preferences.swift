import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let sourceName = "sourceName"
        static let frameRate = "frameRate"
        static let showsCursor = "showsCursor"
        static let selectedDisplay = "selectedDisplay"
        static let launchAtLogin = "launchAtLogin"
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
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sourceName = defaults.string(forKey: Key.sourceName) ?? "Sanctuary Projector Screen"
        frameRate = defaults.object(forKey: Key.frameRate) as? Int ?? 60
        showsCursor = defaults.object(forKey: Key.showsCursor) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        if let data = defaults.data(forKey: Key.selectedDisplay) {
            selectedDisplay = try? JSONDecoder().decode(DisplayIdentity.self, from: data)
        } else { selectedDisplay = nil }
    }
}
