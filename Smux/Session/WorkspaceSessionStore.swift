import Combine
import Foundation

@MainActor
protocol WorkspaceSessionReading: AnyObject {
    func session(for id: WorkspaceSession.ID) -> WorkspaceSession?
    func sessions(in workspaceID: Workspace.ID) -> [WorkspaceSession]
    func sessionID(for content: WorkspaceSessionContentReference) -> WorkspaceSession.ID?
}

@MainActor
final class WorkspaceSessionStore: ObservableObject, WorkspaceSessionReading {
    @Published private(set) var sessions: [WorkspaceSession.ID: WorkspaceSession]
    @Published private(set) var orderedSessionIDs: [WorkspaceSession.ID]

    init(
        sessions: [WorkspaceSession.ID: WorkspaceSession] = [:],
        orderedSessionIDs: [WorkspaceSession.ID] = []
    ) {
        self.sessions = sessions
        self.orderedSessionIDs = orderedSessionIDs.isEmpty ? Array(sessions.keys) : orderedSessionIDs
    }

    func session(for id: WorkspaceSession.ID) -> WorkspaceSession? {
        sessions[id]
    }

    func sessions(in workspaceID: Workspace.ID) -> [WorkspaceSession] {
        orderedSessionIDs.compactMap { sessions[$0] }.filter { $0.workspaceID == workspaceID }
    }

    func sessionID(for content: WorkspaceSessionContentReference) -> WorkspaceSession.ID? {
        sessions.values.first { $0.content == content }?.id
    }

    func upsertSession(_ session: WorkspaceSession) {
        if sessions[session.id] == nil {
            orderedSessionIDs.append(session.id)
        }
        sessions[session.id] = session
    }

    func removeSession(id: WorkspaceSession.ID) {
        sessions.removeValue(forKey: id)
        orderedSessionIDs.removeAll { $0 == id }
    }

    func replaceSessions(_ restoredSessions: [WorkspaceSession]) {
        sessions = Dictionary(uniqueKeysWithValues: restoredSessions.map { ($0.id, $0) })
        orderedSessionIDs = restoredSessions.map(\.id)
    }

    func replaceSessions(
        in workspaceID: Workspace.ID,
        with restoredSessions: [WorkspaceSession]
    ) {
        let removedIDs = Set(
            sessions.values
                .filter { $0.workspaceID == workspaceID }
                .map(\.id)
        )
        sessions = sessions.filter { !removedIDs.contains($0.key) }
        orderedSessionIDs.removeAll { removedIDs.contains($0) }

        for session in restoredSessions {
            upsertSession(session)
        }
    }

    func removeSessions(in workspaceID: Workspace.ID) {
        let removedIDs = Set(
            sessions.values
                .filter { $0.workspaceID == workspaceID }
                .map(\.id)
        )
        sessions = sessions.filter { !removedIDs.contains($0.key) }
        orderedSessionIDs.removeAll { removedIDs.contains($0) }
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

    func snapshotSessions() -> [WorkspaceSession] {
        let orderedSessions = orderedSessionIDs.compactMap { sessions[$0] }
        let orderedIDs = Set(orderedSessions.map(\.id))
        return orderedSessions + sessions.values.filter { !orderedIDs.contains($0.id) }
    }

    func snapshotSessions(in workspaceID: Workspace.ID) -> [WorkspaceSession] {
        snapshotSessions().filter { $0.workspaceID == workspaceID }
    }
}
