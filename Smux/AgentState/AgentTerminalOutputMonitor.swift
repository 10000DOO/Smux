import Foundation

@MainActor
final class AgentTerminalOutputMonitor {
    private let detector: AgentStatusDetector
    private let stateStore: AgentStateStore
    private let notificationStore: NotificationStore

    init(
        detector: AgentStatusDetector = AgentStatusDetector(),
        stateStore: AgentStateStore,
        notificationStore: NotificationStore
    ) {
        self.detector = detector
        self.stateStore = stateStore
        self.notificationStore = notificationStore
    }

    @discardableResult
    func ingest(
        output data: Data,
        sessionID: TerminalSession.ID,
        workspaceID: Workspace.ID,
        panelID: PanelNode.ID?
    ) -> AgentNotification? {
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return ingest(
            output: output,
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )
    }

    @discardableResult
    func ingest(
        output: String,
        sessionID: TerminalSession.ID,
        workspaceID: Workspace.ID,
        panelID: PanelNode.ID?
    ) -> AgentNotification? {
        guard let status = detector.detectStatus(from: output, sessionID: sessionID),
              let transition = stateStore.ingest(status, sessionID: sessionID),
              let notification = Self.notification(
                for: transition,
                workspaceID: workspaceID,
                panelID: panelID
              ) else {
            return nil
        }

        notificationStore.ingest(notification)
        return notification
    }

    func reset(sessionID: TerminalSession.ID) {
        detector.reset(sessionID: sessionID)
        stateStore.reset(sessionID: sessionID)
    }

    private static func notification(
        for transition: AgentStateTransition,
        workspaceID: Workspace.ID,
        panelID: PanelNode.ID?
    ) -> AgentNotification? {
        guard let kind = AgentNotificationKind(state: transition.currentStatus.state) else {
            return nil
        }

        return AgentNotification(
            id: transition.id,
            workspaceID: workspaceID,
            panelID: panelID,
            sessionID: transition.sessionID,
            level: NotificationLevel(kind: kind),
            kind: kind,
            message: transition.currentStatus.message ?? kind.defaultMessage,
            createdAt: transition.createdAt,
            acknowledgedAt: nil
        )
    }
}

private extension AgentNotificationKind {
    init?(state: AgentExecutionState) {
        switch state {
        case .waitingForInput:
            self = .waitingForInput
        case .permissionRequested:
            self = .permissionRequested
        case .completed:
            self = .completed
        case .failed:
            self = .failed
        case .terminated:
            self = .terminated
        case .idle, .running, .unknown:
            return nil
        }
    }

    var defaultMessage: String {
        switch self {
        case .waitingForInput:
            return "Agent is waiting for input"
        case .permissionRequested:
            return "Agent requested permission"
        case .completed:
            return "Agent completed"
        case .failed:
            return "Agent failed"
        case .terminated:
            return "Agent terminated"
        }
    }
}

private extension NotificationLevel {
    init(kind: AgentNotificationKind) {
        switch kind {
        case .completed:
            self = .info
        case .waitingForInput, .permissionRequested, .terminated:
            self = .warning
        case .failed:
            self = .error
        }
    }
}
