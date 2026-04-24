import Foundation

nonisolated struct SystemNotificationDelivery: Codable, Hashable {
    var identifier: String
    var title: String
    var body: String
    var interruption: SystemNotificationInterruption
    var userInfo: [String: String]
}

nonisolated enum SystemNotificationInterruption: String, Codable, Hashable {
    case passive
    case active
    case timeSensitive
}

nonisolated struct SystemNotificationDeliveryFactory: Codable, Hashable {
    static let `default` = SystemNotificationDeliveryFactory()

    func delivery(for notification: AgentNotification) -> SystemNotificationDelivery {
        SystemNotificationDelivery(
            identifier: notification.id.uuidString,
            title: title(for: notification.kind),
            body: notification.message,
            interruption: interruption(for: notification.kind),
            userInfo: [
                "workspaceNotificationID": notification.id.uuidString,
                "workspaceID": notification.workspaceID.uuidString,
                "sessionID": notification.sessionID.uuidString
            ]
        )
    }

    private func title(for kind: AgentNotificationKind) -> String {
        switch kind {
        case .completed:
            return "Smux task completed"
        case .permissionRequested:
            return "Smux needs approval"
        case .waitingForInput, .failed, .terminated:
            return "Smux"
        }
    }

    private func interruption(for kind: AgentNotificationKind) -> SystemNotificationInterruption {
        switch kind {
        case .permissionRequested:
            return .active
        case .completed, .waitingForInput, .failed, .terminated:
            return .passive
        }
    }
}

@MainActor
protocol SystemNotificationDelivering {
    func prepare(completionHandler: @escaping @MainActor (Result<Bool, any Error>) -> Void)
    func deliver(
        _ delivery: SystemNotificationDelivery,
        completionHandler: @escaping @MainActor (Result<Void, any Error>) -> Void
    )
}

@MainActor
struct NoopSystemNotificationDeliverer: SystemNotificationDelivering {
    func prepare(completionHandler: @escaping @MainActor (Result<Bool, any Error>) -> Void) {
        completionHandler(.success(false))
    }

    func deliver(
        _ delivery: SystemNotificationDelivery,
        completionHandler: @escaping @MainActor (Result<Void, any Error>) -> Void
    ) {
        completionHandler(.success(()))
    }
}
