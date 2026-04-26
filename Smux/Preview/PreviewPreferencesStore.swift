import Combine
import Foundation

@MainActor
final class PreviewPreferencesStore: ObservableObject {
    @Published var externalLinkPolicy: PreviewExternalLinkPolicy {
        didSet {
            defaults.set(externalLinkPolicy.rawValue, forKey: Keys.externalLinkPolicy)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.externalLinkPolicy = Self.loadExternalLinkPolicy(from: defaults)
    }

    private static func loadExternalLinkPolicy(from defaults: UserDefaults) -> PreviewExternalLinkPolicy {
        guard let rawValue = defaults.string(forKey: Keys.externalLinkPolicy) else {
            return .block
        }

        return PreviewExternalLinkPolicy(rawValue: rawValue) ?? .block
    }

    private enum Keys {
        static let externalLinkPolicy = "preview.externalLinkPolicy"
    }
}
