import Combine
import Foundation

@MainActor
final class WorkspaceLayoutSessionStore: ObservableObject {
    @Published private(set) var sessions: [WorkspaceLayoutSession.ID: WorkspaceLayoutSession]
    @Published private(set) var orderedSessionIDs: [WorkspaceLayoutSession.ID]
    @Published private(set) var activeSessionIDs: [Workspace.ID: WorkspaceLayoutSession.ID]

    init(
        sessions: [WorkspaceLayoutSession.ID: WorkspaceLayoutSession] = [:],
        orderedSessionIDs: [WorkspaceLayoutSession.ID] = [],
        activeSessionIDs: [Workspace.ID: WorkspaceLayoutSession.ID] = [:]
    ) {
        self.sessions = sessions
        self.orderedSessionIDs = orderedSessionIDs.isEmpty ? Array(sessions.keys) : orderedSessionIDs
        self.activeSessionIDs = activeSessionIDs
    }

    func session(for id: WorkspaceLayoutSession.ID) -> WorkspaceLayoutSession? {
        sessions[id]
    }

    func sessions(in workspaceID: Workspace.ID) -> [WorkspaceLayoutSession] {
        orderedSessionIDs.compactMap { sessions[$0] }.filter { $0.workspaceID == workspaceID }
    }

    func activeSessionID(in workspaceID: Workspace.ID) -> WorkspaceLayoutSession.ID? {
        activeSessionIDs[workspaceID]
    }

    func activeSession(in workspaceID: Workspace.ID) -> WorkspaceLayoutSession? {
        activeSessionIDs[workspaceID].flatMap { sessions[$0] }
    }

    @discardableResult
    func ensureActiveSession(
        in workspaceID: Workspace.ID,
        panelTree: PanelNode = .leaf(surface: .empty),
        focusedPanelID: PanelNode.ID? = nil
    ) -> WorkspaceLayoutSession {
        if let activeSession = activeSession(in: workspaceID) {
            return activeSession
        }

        if let firstSession = sessions(in: workspaceID).first {
            activeSessionIDs[workspaceID] = firstSession.id
            return firstSession
        }

        let session = WorkspaceLayoutSession(
            workspaceID: workspaceID,
            title: nextTitle(in: workspaceID),
            panelTree: panelTree,
            focusedPanelID: focusedPanelID
        )
        upsertSession(session)
        activeSessionIDs[workspaceID] = session.id
        return session
    }

    @discardableResult
    func createSession(
        in workspaceID: Workspace.ID,
        panelTree: PanelNode = .leaf(surface: .empty),
        focusedPanelID: PanelNode.ID? = nil
    ) -> WorkspaceLayoutSession {
        let session = WorkspaceLayoutSession(
            workspaceID: workspaceID,
            title: nextTitle(in: workspaceID),
            panelTree: panelTree,
            focusedPanelID: focusedPanelID
        )
        upsertSession(session)
        activeSessionIDs[workspaceID] = session.id
        return session
    }

    func activateSession(id sessionID: WorkspaceLayoutSession.ID) {
        guard let session = sessions[sessionID] else {
            return
        }

        activeSessionIDs[session.workspaceID] = session.id
        updateLastActiveAt(sessionID: session.id)
    }

    func updateActiveSession(
        in workspaceID: Workspace.ID,
        panelTree: PanelNode,
        focusedPanelID: PanelNode.ID?
    ) {
        let session = ensureActiveSession(
            in: workspaceID,
            panelTree: panelTree,
            focusedPanelID: focusedPanelID
        )
        updateSession(
            id: session.id,
            panelTree: panelTree,
            focusedPanelID: focusedPanelID,
            lastActiveAt: Date()
        )
    }

    func replaceSessions(
        in workspaceID: Workspace.ID,
        with restoredSessions: [WorkspaceLayoutSession],
        activeSessionID: WorkspaceLayoutSession.ID?,
        fallbackPanelTree: PanelNode = .leaf(surface: .empty),
        fallbackFocusedPanelID: PanelNode.ID? = nil
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

        if let activeSessionID,
           sessions[activeSessionID]?.workspaceID == workspaceID {
            activeSessionIDs[workspaceID] = activeSessionID
        } else if let firstSession = sessions(in: workspaceID).first {
            activeSessionIDs[workspaceID] = firstSession.id
        } else {
            let session = WorkspaceLayoutSession(
                workspaceID: workspaceID,
                title: nextTitle(in: workspaceID),
                panelTree: fallbackPanelTree,
                focusedPanelID: fallbackFocusedPanelID
            )
            upsertSession(session)
            activeSessionIDs[workspaceID] = session.id
        }
    }

    func removeSession(id sessionID: WorkspaceLayoutSession.ID) -> WorkspaceLayoutSession? {
        guard let removedSession = sessions.removeValue(forKey: sessionID) else {
            return nil
        }

        orderedSessionIDs.removeAll { $0 == sessionID }

        if activeSessionIDs[removedSession.workspaceID] == sessionID {
            activeSessionIDs[removedSession.workspaceID] = sessions(in: removedSession.workspaceID).first?.id
        }

        return removedSession
    }

    func removeSessions(in workspaceID: Workspace.ID) {
        let removedIDs = Set(
            sessions.values
                .filter { $0.workspaceID == workspaceID }
                .map(\.id)
        )
        sessions = sessions.filter { !removedIDs.contains($0.key) }
        orderedSessionIDs.removeAll { removedIDs.contains($0) }
        activeSessionIDs.removeValue(forKey: workspaceID)
    }

    func moveSessions(from sourceWorkspaceID: Workspace.ID, to targetWorkspaceID: Workspace.ID) {
        guard sourceWorkspaceID != targetWorkspaceID else {
            return
        }

        for (sessionID, var session) in sessions where session.workspaceID == sourceWorkspaceID {
            session.workspaceID = targetWorkspaceID
            sessions[sessionID] = session
        }

        if let activeSessionID = activeSessionIDs.removeValue(forKey: sourceWorkspaceID) {
            activeSessionIDs[targetWorkspaceID] = activeSessionID
        }
    }

    func snapshotSessions(in workspaceID: Workspace.ID) -> [WorkspaceLayoutSession] {
        sessions(in: workspaceID)
    }

    private func upsertSession(_ session: WorkspaceLayoutSession) {
        if sessions[session.id] == nil {
            orderedSessionIDs.append(session.id)
        }
        sessions[session.id] = session
    }

    private func updateSession(
        id sessionID: WorkspaceLayoutSession.ID,
        panelTree: PanelNode,
        focusedPanelID: PanelNode.ID?,
        lastActiveAt: Date
    ) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.panelTree = panelTree
        session.focusedPanelID = focusedPanelID ?? panelTree.firstLeafID
        session.lastActiveAt = lastActiveAt
        sessions[sessionID] = session
    }

    private func updateLastActiveAt(sessionID: WorkspaceLayoutSession.ID) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.lastActiveAt = Date()
        sessions[sessionID] = session
    }

    private func nextTitle(in workspaceID: Workspace.ID) -> String {
        "Session \(sessions(in: workspaceID).count + 1)"
    }
}
