import Foundation

nonisolated struct AgentStateTransition: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var sessionID: TerminalSession.ID
    var previousStatus: AgentStatus?
    var currentStatus: AgentStatus
    var createdAt: Date
}

final class AgentStateStore {
    private(set) var statusesBySession: [TerminalSession.ID: AgentStatus]
    private(set) var transitions: [AgentStateTransition]

    init(
        statusesBySession: [TerminalSession.ID: AgentStatus] = [:],
        transitions: [AgentStateTransition] = []
    ) {
        self.statusesBySession = statusesBySession
        self.transitions = transitions
    }

    @discardableResult
    func ingest(_ status: AgentStatus, sessionID: TerminalSession.ID) -> AgentStateTransition? {
        let previousStatus = statusesBySession[sessionID]
        statusesBySession[sessionID] = status

        if previousStatus?.hasSameTransitionIdentity(as: status) == true {
            return nil
        }

        let transition = AgentStateTransition(
            id: AgentStateTransition.ID(),
            sessionID: sessionID,
            previousStatus: previousStatus,
            currentStatus: status,
            createdAt: status.updatedAt
        )
        transitions.append(transition)
        return transition
    }

    func status(for sessionID: TerminalSession.ID) -> AgentStatus? {
        statusesBySession[sessionID]
    }

    func reset(sessionID: TerminalSession.ID) {
        statusesBySession.removeValue(forKey: sessionID)
    }
}

private extension AgentStatus {
    func hasSameTransitionIdentity(as other: AgentStatus) -> Bool {
        agentKind == other.agentKind
            && state == other.state
            && message == other.message
    }
}
