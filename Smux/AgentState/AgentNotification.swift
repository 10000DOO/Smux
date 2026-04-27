import Foundation

nonisolated enum NotificationLevel: String, Codable, Hashable {
    case info
    case warning
    case error
    case critical
}

nonisolated enum AgentNotificationKind: String, Codable, Hashable {
    case waitingForInput
    case permissionRequested
    case completed
    case failed
    case terminated
}

nonisolated struct AgentNotification: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var panelID: PanelNode.ID?
    var sessionID: TerminalSession.ID
    var workspaceSessionID: WorkspaceSession.ID? = nil
    var level: NotificationLevel
    var kind: AgentNotificationKind
    var message: String
    var createdAt: Date
    var acknowledgedAt: Date?
}
