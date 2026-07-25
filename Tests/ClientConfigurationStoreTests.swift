import XCTest
@testable import Spotlightify

final class ClientConfigurationStoreTests: XCTestCase {
    func testFallsBackToBundledClientIDWhenNoUserValueExists() {
        let defaults = makeDefaults()
        let store = ClientConfigurationStore(defaults: defaults, bundledClientID: "bundled12345678901234567890")

        XCTAssertEqual(store.currentClientID(), "bundled12345678901234567890")
        XCTAssertTrue(store.hasConfiguredClientID)
        XCTAssertFalse(store.hasUserConfiguredClientID)
    }

    func testSaveClientIDPersistsUserValue() throws {
        let defaults = makeDefaults()
        let store = ClientConfigurationStore(defaults: defaults, bundledClientID: "")

        try store.saveClientID("abc123def456ghi789jkl012mno345pq")

        XCTAssertEqual(store.currentClientID(), "abc123def456ghi789jkl012mno345pq")
        XCTAssertTrue(store.hasUserConfiguredClientID)
    }

    func testInvalidClientIDIsRejected() {
        let defaults = makeDefaults()
        let store = ClientConfigurationStore(defaults: defaults, bundledClientID: "")

        XCTAssertThrowsError(try store.saveClientID("not valid")) { error in
            XCTAssertEqual(error as? ClientConfigurationError, .invalidClientID)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SpotlightifyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
