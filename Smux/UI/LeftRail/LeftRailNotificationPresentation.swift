import Foundation

nonisolated struct LeftRailNotificationSummary: Equatable {
    var waitingCount: Int
    var completedCount: Int
    var failedCount: Int
    var totalCount: Int

    static let empty = LeftRailNotificationSummary(
        waitingCount: 0,
        completedCount: 0,
        failedCount: 0,
        totalCount: 0
    )

    static func make(from notifications: [WorkspaceNotification]) -> LeftRailNotificationSummary {
        LeftRailNotificationSummary(
            waitingCount: notifications.filter { $0.isWaitingAgentNotification }.count,
            completedCount: notifications.filter { $0.agentKind == .completed }.count,
            failedCount: notifications.filter { $0.isFailedAgentNotification }.count,
            totalCount: notifications.count
        )
    }

    var items: [LeftRailNotificationSummaryItem] {
        [
            LeftRailNotificationSummaryItem(title: "Waiting", count: waitingCount, systemImage: "hourglass"),
            LeftRailNotificationSummaryItem(title: "Done", count: completedCount, systemImage: "checkmark.circle"),
            LeftRailNotificationSummaryItem(title: "Failed", count: failedCount, systemImage: "exclamationmark.triangle"),
        ].filter { $0.count > 0 }
    }
}

nonisolated struct LeftRailNotificationSummaryItem: Identifiable, Equatable {
    var title: String
    var count: Int
    var systemImage: String

    var id: String {
        title
    }
}

nonisolated struct LeftRailNotificationPresentation: Equatable {
    var title: String
    var systemImage: String
    var message: String
    var showsAcknowledge: Bool

    init(notification: WorkspaceNotification) {
        title = notification.agentKind?.leftRailTitle ?? notification.level.leftRailTitle
        systemImage = notification.agentKind?.leftRailSystemImage ?? notification.level.leftRailSystemImage
        message = notification.message
        showsAcknowledge = notification.acknowledgedAt == nil
    }
}

private extension WorkspaceNotification {
    nonisolated var isWaitingAgentNotification: Bool {
        agentKind == .waitingForInput || agentKind == .permissionRequested
    }

    nonisolated var isFailedAgentNotification: Bool {
        agentKind == .failed || agentKind == .terminated
    }
}

private extension AgentNotificationKind {
    nonisolated var leftRailTitle: String {
        switch self {
        case .waitingForInput:
            return "Waiting"
        case .permissionRequested:
            return "Permission"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .terminated:
            return "Terminated"
        }
    }

    nonisolated var leftRailSystemImage: String {
        switch self {
        case .waitingForInput:
            return "hourglass"
        case .permissionRequested:
            return "hand.raised"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .terminated:
            return "stop.circle"
        }
    }
}

private extension NotificationLevel {
    nonisolated var leftRailTitle: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .critical:
            return "Critical"
        }
    }

    nonisolated var leftRailSystemImage: String {
        switch self {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        case .critical:
            return "exclamationmark.octagon"
        }
    }
}
