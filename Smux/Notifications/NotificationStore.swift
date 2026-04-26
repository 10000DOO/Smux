import Combine
import Foundation

@MainActor
final class NotificationStore: ObservableObject {
    @Published var notifications: [WorkspaceNotification] = []
    @Published var policy: NotificationRoutingPolicy {
        didSet {
            rerouteNotifications()
        }
    }

    private let systemNotifier: any SystemNotificationDelivering
    private let systemDeliveryFactory: SystemNotificationDeliveryFactory
    private let clock: () -> Date
    private let maximumNotificationHistoryCount: Int
    private var deliveredSystemNotificationIDs: Set<AgentNotification.ID> = []
    private var pendingSystemNotificationIDs: Set<AgentNotification.ID> = []

    init(
        policy: NotificationRoutingPolicy = .default,
        systemNotifier: any SystemNotificationDelivering = NoopSystemNotificationDeliverer(),
        systemDeliveryFactory: SystemNotificationDeliveryFactory = .default,
        maximumNotificationHistoryCount: Int = 512,
        clock: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.systemNotifier = systemNotifier
        self.systemDeliveryFactory = systemDeliveryFactory
        self.maximumNotificationHistoryCount = max(1, maximumNotificationHistoryCount)
        self.clock = clock
    }

    func ingest(_ notification: AgentNotification) {
        let existingNotification = notifications.first { $0.id == notification.id }
        let acknowledgedAt = notification.acknowledgedAt ?? existingNotification?.acknowledgedAt
        var routedNotification = notification
        routedNotification.acknowledgedAt = acknowledgedAt

        let workspaceNotification = WorkspaceNotification(
            id: notification.id,
            workspaceID: notification.workspaceID,
            source: .agent(notification.id),
            level: notification.level,
            agentKind: notification.kind,
            message: notification.message,
            createdAt: notification.createdAt,
            routing: policy.route(routedNotification),
            acknowledgedAt: acknowledgedAt
        )

        if let index = notifications.firstIndex(where: { $0.id == workspaceNotification.id }) {
            notifications[index] = workspaceNotification
        } else {
            notifications.insert(workspaceNotification, at: 0)
        }
        pruneNotificationHistory()

        if shouldDeliverSystemNotification(for: routedNotification) {
            let notificationID = routedNotification.id
            pendingSystemNotificationIDs.insert(notificationID)
            systemNotifier.deliver(systemDeliveryFactory.delivery(for: routedNotification)) { [weak self] result in
                self?.finishSystemNotificationDelivery(notificationID, result: result)
            }
        }
    }

    func acknowledge(id: WorkspaceNotification.ID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else {
            return
        }

        var notification = notifications[index]
        notification.acknowledgedAt = clock()
        notification.routing = policy.route(
            panelID: notification.routing.panelID,
            level: notification.level,
            acknowledgedAt: notification.acknowledgedAt
        )
        notifications[index] = notification
    }

    func mostRecentVisibleNotificationID(workspaceID: Workspace.ID?) -> WorkspaceNotification.ID? {
        var selectedNotification: WorkspaceNotification?

        for notification in notifications where isVisible(notification, workspaceID: workspaceID) {
            guard let currentSelection = selectedNotification else {
                selectedNotification = notification
                continue
            }

            if notification.createdAt > currentSelection.createdAt {
                selectedNotification = notification
            }
        }

        return selectedNotification?.id
    }

    private func shouldDeliverSystemNotification(for notification: AgentNotification) -> Bool {
        policy.allowsSystemDelivery(for: notification)
            && !deliveredSystemNotificationIDs.contains(notification.id)
            && !pendingSystemNotificationIDs.contains(notification.id)
    }

    private func isVisible(_ notification: WorkspaceNotification, workspaceID: Workspace.ID?) -> Bool {
        notification.acknowledgedAt == nil
            && notification.routing.shouldShowInLeftRail
            && (workspaceID == nil || notification.workspaceID == workspaceID)
    }

    private func finishSystemNotificationDelivery(
        _ id: AgentNotification.ID,
        result: Result<Void, any Error>
    ) {
        pendingSystemNotificationIDs.remove(id)

        if case .success = result,
           notifications.contains(where: { $0.id == id }) {
            deliveredSystemNotificationIDs.insert(id)
        }
    }

    private func pruneNotificationHistory() {
        if notifications.count > maximumNotificationHistoryCount {
            notifications.removeLast(notifications.count - maximumNotificationHistoryCount)
        }

        let retainedNotificationIDs = Set(notifications.map(\.id))
        deliveredSystemNotificationIDs.formIntersection(retainedNotificationIDs)
    }

    private func rerouteNotifications() {
        notifications = notifications.map { notification in
            var reroutedNotification = notification
            reroutedNotification.routing = policy.route(
                panelID: notification.routing.panelID,
                level: notification.level,
                acknowledgedAt: notification.acknowledgedAt
            )
            return reroutedNotification
        }
    }
}
