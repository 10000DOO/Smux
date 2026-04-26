import XCTest
@testable import Smux

final class PreviewPreferencesStoreTests: XCTestCase {
    @MainActor
    func testPreviewPreferencesStoreDefaultsExternalLinksToBlocked() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let store = PreviewPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.externalLinkPolicy, .block)
    }

    @MainActor
    func testPreviewPreferencesStorePersistsExternalLinkPolicy() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let store = PreviewPreferencesStore(defaults: defaults)
        store.externalLinkPolicy = .openInDefaultBrowser

        let restoredStore = PreviewPreferencesStore(defaults: defaults)
        XCTAssertEqual(restoredStore.externalLinkPolicy, .openInDefaultBrowser)
    }

    private var defaultsSuiteName: String {
        "SmuxTests.PreviewPreferencesStoreTests"
    }

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}
