import Foundation

nonisolated enum PreviewExternalLinkPolicy: String, CaseIterable, Codable, Hashable {
    case block
    case openInDefaultBrowser

    var title: String {
        switch self {
        case .block:
            return "Block External Links"
        case .openInDefaultBrowser:
            return "Open External Links"
        }
    }

    var statusText: String {
        switch self {
        case .block:
            return "Blocked"
        case .openInDefaultBrowser:
            return "Open"
        }
    }
}
