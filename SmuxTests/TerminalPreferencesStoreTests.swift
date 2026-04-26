import XCTest
@testable import Smux

final class TerminalPreferencesStoreTests: XCTestCase {
    @MainActor
    func testTerminalPreferencesStoreUsesDefaults() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let store = TerminalPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.fontSize, TerminalAppearance.defaultFontSize)
        XCTAssertEqual(store.appearance, TerminalAppearance())
    }

    @MainActor
    func testTerminalPreferencesStorePersistsThemeAndFontSize() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let store = TerminalPreferencesStore(defaults: defaults)
        store.theme = .dark
        store.adjustFontSize(by: TerminalAppearance.fontSizeStep * 2)

        let restoredStore = TerminalPreferencesStore(defaults: defaults)
        XCTAssertEqual(restoredStore.theme, .dark)
        XCTAssertEqual(
            restoredStore.fontSize,
            TerminalAppearance.defaultFontSize + TerminalAppearance.fontSizeStep * 2
        )
    }

    @MainActor
    func testTerminalPreferencesStoreClampsFontSize() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let store = TerminalPreferencesStore(defaults: defaults)
        store.fontSize = TerminalAppearance.maximumFontSize + 10
        XCTAssertEqual(store.fontSize, TerminalAppearance.maximumFontSize)

        store.fontSize = TerminalAppearance.minimumFontSize - 10
        XCTAssertEqual(store.fontSize, TerminalAppearance.minimumFontSize)
    }

    @MainActor
    func testTerminalPreferencesStoreFallsBackForInvalidPersistedFontSize() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("bad", forKey: "terminal.fontSize")

        let store = TerminalPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.fontSize, TerminalAppearance.defaultFontSize)
    }

    private var defaultsSuiteName: String {
        "SmuxTests.TerminalPreferencesStoreTests"
    }

    private func isolatedDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            XCTFail("Failed to create isolated defaults.")
            return .standard
        }

        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}
