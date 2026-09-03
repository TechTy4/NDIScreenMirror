import XCTest
@testable import SanctuaryCore

final class SanctuaryCoreTests: XCTestCase {
    func testMagewellSourceMatchingPrefersExactThenUniqueSubstring() throws {
        let sources = [
            MagewellSource(id: 1, name: "SANCTUARY (ProPresenter)", address: "10.0.0.1:5961"),
            MagewellSource(id: 2, name: "BIGMAC (Sanctuary Projector Screen)", address: "10.0.0.2:5961")
        ]
        XCTAssertEqual(try MagewellClient.bestMatch("SANCTUARY (ProPresenter)", in: sources).id, 1)
        XCTAssertEqual(try MagewellClient.bestMatch("projector screen", in: sources).id, 2)
    }

    func testMagewellSourceMatchingRejectsAmbiguity() {
        let sources = [
            MagewellSource(id: 1, name: "Room A ProPresenter", address: nil),
            MagewellSource(id: 2, name: "Room B ProPresenter", address: nil)
        ]
        XCTAssertThrowsError(try MagewellClient.bestMatch("ProPresenter", in: sources))
    }

    func testModernMagewellSourceShapesAreParsed() throws {
        let object: [String: Any] = [
            "status": 0,
            "list": [
                ["id": 7, "config": ["name": "Preset alias", "type": 2, "ndi": ["name": "HOST (ProPresenter)", "url": "10.0.0.1:5961"]]],
                ["id": 8, "config": ["name": "Input", "type": "d_ndi", "data": ["name": "HOST (Monitor)", "url": "10.0.0.2:5961"]]]
            ]
        ]
        let sources = try MagewellClient.parseModernSources(object)
        XCTAssertEqual(sources.map(\.name), ["HOST (ProPresenter)", "HOST (Monitor)"])
        XCTAssertEqual(sources.map(\.address), ["10.0.0.1:5961", "10.0.0.2:5961"])
    }

    private func identity(
        uuid: String? = nil, vendor: UInt32 = 1, model: UInt32 = 2,
        serial: UInt32 = 3, name: String = "Projector", width: Int = 1920, height: Int = 1080
    ) -> DisplayIdentity {
        DisplayIdentity(uuid: uuid, vendorID: vendor, modelID: model, serialNumber: serial,
                        name: name, nativeWidth: width, nativeHeight: height)
    }

    func testIdentityRoundTrip() throws {
        let original = identity(uuid: "display-uuid")
        let decoded = try JSONDecoder().decode(DisplayIdentity.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testUUIDAlwaysWinsMatching() {
        let saved = identity(uuid: "stable", vendor: 10, model: 20, serial: 30)
        let moved = DisplayDescriptor(id: 99, identity: identity(uuid: "stable", vendor: 999, model: 999, serial: 0),
                                      width: 2560, height: 1440, isMain: false)
        XCTAssertEqual(DisplayIdentity.bestMatch(for: saved, in: [moved])?.id, 99)
    }

    func testSerialVendorModelMatchSurvivesUUIDChange() {
        let saved = identity(uuid: "old")
        let changed = DisplayDescriptor(id: 7, identity: identity(uuid: "new"),
                                        width: 1920, height: 1080, isMain: true)
        XCTAssertEqual(DisplayIdentity.bestMatch(for: saved, in: [changed])?.id, 7)
    }

    func testAmbiguousWeakMatchDoesNotSelectWrongDisplay() {
        let saved = identity(uuid: nil, vendor: 0, model: 0, serial: 0, name: "Generic")
        let a = DisplayDescriptor(id: 1, identity: identity(uuid: "a", vendor: 0, model: 0, serial: 0, name: "Generic"),
                                  width: 1920, height: 1080, isMain: true)
        let b = DisplayDescriptor(id: 2, identity: identity(uuid: "b", vendor: 0, model: 0, serial: 0, name: "Generic"),
                                  width: 1920, height: 1080, isMain: false)
        XCTAssertNil(DisplayIdentity.bestMatch(for: saved, in: [a, b]))
    }

    func testNoFallbackForUnrelatedMonitor() {
        let saved = identity(uuid: "missing", vendor: 10, model: 20, serial: 30, name: "Old")
        let unrelated = DisplayDescriptor(id: 4, identity: identity(uuid: "other", vendor: 99, model: 88, serial: 77, name: "New"),
                                          width: 3840, height: 2160, isMain: true)
        XCTAssertNil(DisplayIdentity.bestMatch(for: saved, in: [unrelated]))
    }

    func testRecoveryBackoffCapsAndResets() {
        var backoff = RecoveryBackoff(maximum: 8)
        XCTAssertEqual([backoff.nextDelay(), backoff.nextDelay(), backoff.nextDelay(),
                        backoff.nextDelay(), backoff.nextDelay()], [1, 2, 4, 8, 8])
        backoff.reset()
        XCTAssertEqual(backoff.nextDelay(), 1)
    }

    @MainActor
    func testPreferencesPersistence() {
        let suite = "SanctuaryCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Preferences(defaults: defaults)
        first.sourceName = "Test Sender"
        first.frameRate = 30
        first.showsCursor = false
        first.selectedDisplay = identity(uuid: "saved")
        first.confidenceDisplay = identity(uuid: "confidence")
        first.inputDisplayLabel = "Left Screen"
        first.magewellAddress = "10.0.0.10"

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.sourceName, "Test Sender")
        XCTAssertEqual(second.frameRate, 30)
        XCTAssertFalse(second.showsCursor)
        XCTAssertEqual(second.selectedDisplay, identity(uuid: "saved"))
        XCTAssertEqual(second.confidenceDisplay, identity(uuid: "confidence"))
        XCTAssertEqual(second.inputDisplayLabel, "Left Screen")
        XCTAssertEqual(second.magewellAddress, "10.0.0.10")
    }
}
