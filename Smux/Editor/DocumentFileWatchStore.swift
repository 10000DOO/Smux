import Combine
import Foundation

nonisolated struct DocumentFileWatchEvent: Identifiable, Equatable, Sendable {
    var id = UUID()
    var documentID: DocumentSession.ID
    var event: FileWatchEvent
}

@MainActor
final class DocumentFileWatchStore: ObservableObject {
    @Published private(set) var latestEvents: [DocumentSession.ID: DocumentFileWatchEvent] = [:]

    private let fileWatcher: any FileWatching
    private var scopesByDocumentID: [DocumentSession.ID: FileWatchScope] = [:]
    private var documentIDsByScope: [FileWatchScope: Set<DocumentSession.ID>] = [:]

    init(fileWatcher: any FileWatching = LocalFileWatcher()) {
        self.fileWatcher = fileWatcher
        self.fileWatcher.eventHandler = { [weak self] events in
            Task { @MainActor in
                self?.route(events)
            }
        }
    }

    func startWatching(session: DocumentSession) throws {
        try startWatching(documentID: session.id, url: session.url)
    }

    func restartWatching(session: DocumentSession) throws {
        try restartWatching(documentID: session.id, url: session.url)
    }

    func startWatching(documentID: DocumentSession.ID, url: URL) throws {
        let scope = FileWatchScope.openFile(url)

        if scopesByDocumentID[documentID] == scope {
            return
        }

        try fileWatcher.startWatching(scope)

        if let previousScope = scopesByDocumentID[documentID] {
            removeMapping(documentID: documentID, from: previousScope)
        }

        scopesByDocumentID[documentID] = scope
        documentIDsByScope[scope, default: []].insert(documentID)
    }

    func restartWatching(documentID: DocumentSession.ID, url: URL) throws {
        let scope = FileWatchScope.openFile(url)

        guard scopesByDocumentID[documentID] == scope else {
            try startWatching(documentID: documentID, url: url)
            return
        }

        fileWatcher.stopWatching(scope)
        do {
            try fileWatcher.startWatching(scope)
        } catch {
            removeAllMappings(for: scope)
            throw error
        }
    }

    func stopWatching(documentID: DocumentSession.ID) {
        guard let scope = scopesByDocumentID.removeValue(forKey: documentID) else {
            latestEvents[documentID] = nil
            return
        }

        removeMapping(documentID: documentID, from: scope)
    }

    func stopAll() {
        scopesByDocumentID.removeAll()
        documentIDsByScope.removeAll()
        latestEvents.removeAll()
        fileWatcher.stopAll()
    }

    func latestEvent(for documentID: DocumentSession.ID) -> DocumentFileWatchEvent? {
        latestEvents[documentID]
    }

    func eventToken(for documentID: DocumentSession.ID) -> DocumentFileWatchEvent.ID? {
        latestEvents[documentID]?.id
    }

    private func route(_ events: [FileWatchEvent]) {
        for event in events {
            guard let documentIDs = documentIDsByScope[event.scope] else {
                continue
            }

            for documentID in documentIDs {
                latestEvents[documentID] = DocumentFileWatchEvent(
                    documentID: documentID,
                    event: event
                )
            }
        }
    }

    private func removeMapping(documentID: DocumentSession.ID, from scope: FileWatchScope) {
        guard var documentIDs = documentIDsByScope[scope] else {
            latestEvents[documentID] = nil
            return
        }

        documentIDs.remove(documentID)
        latestEvents[documentID] = nil

        if documentIDs.isEmpty {
            documentIDsByScope[scope] = nil
            fileWatcher.stopWatching(scope)
        } else {
            documentIDsByScope[scope] = documentIDs
        }
    }

    private func removeAllMappings(for scope: FileWatchScope) {
        guard let documentIDs = documentIDsByScope.removeValue(forKey: scope) else {
            return
        }

        for documentID in documentIDs {
            scopesByDocumentID.removeValue(forKey: documentID)
            latestEvents[documentID] = nil
        }
    }
}
