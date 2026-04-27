import Foundation

nonisolated struct NotificationRoutingPolicy: Codable, Hashable {
    var showsAcknowledged: Bool
    var minimumLevel: NotificationLevel
    var sendsSystemNotifications: Bool
    var systemDeliveryKinds: Set<AgentNotificationKind>

    static let `default` = NotificationRoutingPolicy()

    init(
        showsAcknowledged: Bool = false,
        minimumLevel: NotificationLevel = .info,
        sendsSystemNotifications: Bool = true,
        systemDeliveryKinds: Set<AgentNotificationKind> = [.completed, .permissionRequested]
    ) {
        self.showsAcknowledged = showsAcknowledged
        self.minimumLevel = minimumLevel
        self.sendsSystemNotifications = sendsSystemNotifications
        self.systemDeliveryKinds = systemDeliveryKinds
    }

    func route(_ notification: AgentNotification) -> WorkspaceNotificationRouting {
        route(
            panelID: notification.panelID,
            workspaceSessionID: notification.workspaceSessionID,
            level: notification.level,
            acknowledgedAt: notification.acknowledgedAt
        )
    }

    func route(
        panelID: PanelNode.ID?,
        workspaceSessionID: WorkspaceSession.ID? = nil,
        level: NotificationLevel,
        acknowledgedAt: Date?
    ) -> WorkspaceNotificationRouting {
        let isVisibleLevel = level.rank >= minimumLevel.rank
        let isAcknowledged = acknowledgedAt != nil
        let shouldShow = isVisibleLevel && (showsAcknowledged || !isAcknowledged)

        return WorkspaceNotificationRouting(
            panelID: panelID,
            workspaceSessionID: workspaceSessionID,
            shouldShowInLeftRail: shouldShow,
            shouldBadgePanel: shouldShow && !isAcknowledged && (workspaceSessionID != nil || panelID != nil)
        )
    }

    func allowsSystemDelivery(for notification: AgentNotification) -> Bool {
        guard sendsSystemNotifications else {
            return false
        }

        guard notification.acknowledgedAt == nil else {
            return false
        }

        return systemDeliveryKinds.contains(notification.kind)
    }
}

extension NotificationLevel {
    nonisolated var rank: Int {
        switch self {
        case .info:
            return 0
        case .warning:
            return 1
        case .error:
            return 2
        case .critical:
            return 3
        }
    }
}
