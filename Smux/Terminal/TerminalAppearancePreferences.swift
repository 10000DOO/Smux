import Combine
import Foundation

nonisolated enum TerminalTheme: String, CaseIterable, Codable, Hashable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return "System Theme"
        case .light:
            return "Light Theme"
        case .dark:
            return "Dark Theme"
        }
    }

    var statusText: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

nonisolated struct TerminalAppearance: Equatable {
    static let defaultFontSize = 13.0
    static let minimumFontSize = 10.0
    static let maximumFontSize = 24.0
    static let fontSizeStep = 1.0

    var theme: TerminalTheme
    var fontSize: Double

    init(
        theme: TerminalTheme = .system,
        fontSize: Double = Self.defaultFontSize
    ) {
        self.theme = theme
        self.fontSize = Self.clampedFontSize(fontSize)
    }

    static func clampedFontSize(_ fontSize: Double) -> Double {
        guard fontSize.isFinite else {
            return defaultFontSize
        }

        return min(max(fontSize, minimumFontSize), maximumFontSize)
    }
}

@MainActor
final class TerminalPreferencesStore: ObservableObject {
    @Published var theme: TerminalTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    @Published var fontSize: Double {
        didSet {
            let clampedFontSize = TerminalAppearance.clampedFontSize(fontSize)
            guard clampedFontSize == fontSize else {
                fontSize = clampedFontSize
                return
            }

            defaults.set(fontSize, forKey: Keys.fontSize)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = Self.loadTheme(from: defaults)
        self.fontSize = Self.loadFontSize(from: defaults)
    }

    var appearance: TerminalAppearance {
        TerminalAppearance(theme: theme, fontSize: fontSize)
    }

    func adjustFontSize(by delta: Double) {
        fontSize = TerminalAppearance.clampedFontSize(fontSize + delta)
    }

    func resetFontSize() {
        fontSize = TerminalAppearance.defaultFontSize
    }

    private static func loadTheme(from defaults: UserDefaults) -> TerminalTheme {
        guard let rawValue = defaults.string(forKey: Keys.theme) else {
            return .system
        }

        return TerminalTheme(rawValue: rawValue) ?? .system
    }

    private static func loadFontSize(from defaults: UserDefaults) -> Double {
        guard let fontSize = defaults.object(forKey: Keys.fontSize) as? NSNumber else {
            return TerminalAppearance.defaultFontSize
        }

        return TerminalAppearance.clampedFontSize(fontSize.doubleValue)
    }

    private enum Keys {
        static let theme = "terminal.theme"
        static let fontSize = "terminal.fontSize"
    }
}
