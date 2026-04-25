import Combine
import Foundation

@MainActor
protocol DocumentSessionStoring: AnyObject {
    func session(for id: DocumentSession.ID) -> DocumentSession?
    func upsertSession(_ session: DocumentSession)
}

@MainActor
final class DocumentSessionStore: ObservableObject, DocumentSessionStoring {
    @Published private(set) var sessions: [DocumentSession.ID: DocumentSession]

    init(sessions: [DocumentSession.ID: DocumentSession] = [:]) {
        self.sessions = sessions
    }

    func session(for id: DocumentSession.ID) -> DocumentSession? {
        sessions[id]
    }

    func upsertSession(_ session: DocumentSession) {
        sessions[session.id] = session
    }

    func replaceSessions(_ restoredSessions: [DocumentSession]) {
        sessions = Dictionary(uniqueKeysWithValues: restoredSessions.map { ($0.id, $0) })
    }

    func snapshotSessions() -> [DocumentSession] {
        Array(sessions.values)
    }
}
