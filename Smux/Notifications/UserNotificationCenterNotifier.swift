import Foundation
import UserNotifications

@MainActor
final class UserNotificationCenterNotifier: NSObject, SystemNotificationDelivering {
    private let center: any UserNotificationScheduling
    nonisolated var foregroundPresentationOptions: UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    init(center: any UserNotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
        super.init()
        self.center.delegate = self
    }

    func prepare(completionHandler: @escaping @MainActor (Result<Bool, any Error>) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { isAuthorized, error in
            Task { @MainActor in
                if let error {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(isAuthorized))
                }
            }
        }
    }

    func deliver(
        _ delivery: SystemNotificationDelivery,
        completionHandler: @escaping @MainActor (Result<Void, any Error>) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = delivery.title
        content.body = delivery.body
        content.sound = .default
        content.interruptionLevel = delivery.interruption.notificationInterruptionLevel
        content.userInfo = delivery.userInfo.reduce(into: [AnyHashable: Any]()) { userInfo, entry in
            userInfo[AnyHashable(entry.key)] = entry.value
        }

        let request = UNNotificationRequest(
            identifier: delivery.identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            Task { @MainActor in
                if let error {
                    completionHandler(.failure(error))
                } else {
                    completionHandler(.success(()))
                }
            }
        }
    }
}

protocol UserNotificationScheduling: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: UserNotificationScheduling {}

extension UserNotificationCenterNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        foregroundPresentationOptions
    }
}

private extension SystemNotificationInterruption {
    var notificationInterruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .passive:
            return .passive
        case .active:
            return .active
        case .timeSensitive:
            return .timeSensitive
        }
    }
}
