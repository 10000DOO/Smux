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

    func replaceSessions(
        in workspaceID: Workspace.ID,
        with restoredSessions: [DocumentSession]
    ) {
        sessions = sessions.filter { $0.value.workspaceID != workspaceID }

        for session in restoredSessions {
            sessions[session.id] = session
        }
    }

    func removeSessions(in workspaceID: Workspace.ID) {
        sessions = sessions.filter { $0.value.workspaceID != workspaceID }
    }

    func moveSessions(from sourceWorkspaceID: Workspace.ID, to targetWorkspaceID: Workspace.ID) {
        guard sourceWorkspaceID != targetWorkspaceID else {
            return
        }

        for (sessionID, var session) in sessions where session.workspaceID == sourceWorkspaceID {
            session.workspaceID = targetWorkspaceID
            sessions[sessionID] = session
        }
    }

    func snapshotSessions() -> [DocumentSession] {
        Array(sessions.values)
    }

    func snapshotSessions(in workspaceID: Workspace.ID) -> [DocumentSession] {
        sessions.values.filter { $0.workspaceID == workspaceID }
    }
}
