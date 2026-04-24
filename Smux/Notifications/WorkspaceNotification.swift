import Foundation

enum WorkspaceNotificationSource: Codable, Hashable {
    case agent(AgentNotification.ID)
    case document(DocumentSession.ID)
    case workspace(Workspace.ID)
    case system
}

struct WorkspaceNotificationRouting: Codable, Hashable {
    var panelID: PanelNode.ID?
    var shouldShowInLeftRail: Bool
    var shouldBadgePanel: Bool
}

struct WorkspaceNotification: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var source: WorkspaceNotificationSource
    var level: NotificationLevel
    var message: String
    var routing: WorkspaceNotificationRouting
    var acknowledgedAt: Date?
}
