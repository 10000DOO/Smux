import Combine
import Foundation

@MainActor
final class NotificationStore: ObservableObject {
    @Published var notifications: [WorkspaceNotification] = []
    @Published var policy = NotificationRoutingPolicy(showsAcknowledged: false, minimumLevel: .info)

    func ingest(_ notification: AgentNotification) {}

    func acknowledge(id: WorkspaceNotification.ID) {}
}
