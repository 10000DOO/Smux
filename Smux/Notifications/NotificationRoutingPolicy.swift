import Foundation

nonisolated struct NotificationRoutingPolicy: Codable, Hashable {
    var showsAcknowledged: Bool
    var minimumLevel: NotificationLevel

    func route(_ notification: AgentNotification) -> WorkspaceNotificationRouting {
        fatalError("TODO")
    }
}
