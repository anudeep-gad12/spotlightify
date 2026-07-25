import XCTest
@testable import Spotlightify

final class AppearancePreferenceStoreTests: XCTestCase {
    func testDefaultsToSystemWhenNoPreferenceExists() {
        let defaults = makeDefaults()

        XCTAssertEqual(AppearancePreferenceStore(defaults: defaults).preference, .system)
    }

    func testPersistsEveryPreference() {
        let defaults = makeDefaults()
        let store = AppearancePreferenceStore(defaults: defaults)

        for preference in AppearancePreference.allCases {
            store.setPreference(preference)
            XCTAssertEqual(AppearancePreferenceStore(defaults: defaults).preference, preference)
        }
    }

    func testInvalidPreferenceFallsBackToSystem() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: "appearance.preference")

        XCTAssertEqual(AppearancePreferenceStore(defaults: defaults).preference, .system)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SpotlightifyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
