import Foundation

nonisolated enum WorkspaceNotificationSource: Codable, Hashable {
    case agent(AgentNotification.ID)
    case document(DocumentSession.ID)
    case workspace(Workspace.ID)
    case system
}

nonisolated struct WorkspaceNotificationRouting: Codable, Hashable {
    var panelID: PanelNode.ID?
    var shouldShowInLeftRail: Bool
    var shouldBadgePanel: Bool
}

nonisolated struct WorkspaceNotification: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var source: WorkspaceNotificationSource
    var level: NotificationLevel
    var agentKind: AgentNotificationKind?
    var message: String
    var createdAt: Date
    var routing: WorkspaceNotificationRouting
    var acknowledgedAt: Date?
}
