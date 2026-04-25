import Foundation

nonisolated enum FileWatchScope: Equatable, Hashable, Codable, Sendable {
    case workspaceRoot(URL)
    case openFile(URL)

    var url: URL {
        switch self {
        case .workspaceRoot(let url), .openFile(let url):
            return url
        }
    }
}

nonisolated enum FileWatchEventKind: String, Codable, Sendable {
    case contentsChanged
    case modified
    case metadataChanged
    case deleted
    case renamed
}

nonisolated struct FileWatchEvent: Equatable, Codable, Sendable {
    var scope: FileWatchScope
    var kind: FileWatchEventKind
    var url: URL

    init(scope: FileWatchScope, kind: FileWatchEventKind, url: URL? = nil) {
        self.scope = scope
        self.kind = kind
        self.url = url ?? scope.url
    }
}

nonisolated protocol FileWatching: AnyObject, Sendable {
    var eventHandler: (@Sendable ([FileWatchEvent]) -> Void)? { get set }

    func startWatching(_ scope: FileWatchScope) throws
    func stopWatching(_ scope: FileWatchScope)
    func stopAll()
}
