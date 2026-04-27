import XCTest
@testable import Smux

final class NotificationStoreTests: XCTestCase {
    @MainActor
    func testNotificationStoreIngestsAndUpdatesAgentNotifications() {
        let notificationID = AgentNotification.ID()
        let workspaceID = Workspace.ID()
        let panelID = PanelNode.ID()
        let sessionID = TerminalSession.ID()
        let workspaceSessionID = WorkspaceSession.ID()
        let notifier = RecordingSystemNotifier()
        let store = NotificationStore(systemNotifier: notifier)
        let original = agentNotification(
            id: notificationID,
            workspaceID: workspaceID,
            panelID: panelID,
            sessionID: sessionID,
            workspaceSessionID: workspaceSessionID,
            level: .warning,
            kind: .waitingForInput,
            message: "Waiting"
        )
        let updated = agentNotification(
            id: notificationID,
            workspaceID: workspaceID,
            panelID: nil,
            sessionID: sessionID,
            level: .error,
            kind: .failed,
            message: "Failed"
        )

        store.ingest(original)
        store.ingest(updated)

        XCTAssertEqual(store.notifications.count, 1)
        XCTAssertEqual(store.notifications.first?.id, notificationID)
        XCTAssertEqual(store.notifications.first?.workspaceID, workspaceID)
        XCTAssertEqual(store.notifications.first?.source, .agent(notificationID))
        XCTAssertEqual(store.notifications.first?.level, .error)
        XCTAssertEqual(store.notifications.first?.agentKind, .failed)
        XCTAssertEqual(store.notifications.first?.message, "Failed")
        XCTAssertEqual(store.notifications.first?.createdAt, updated.createdAt)
        XCTAssertNil(store.notifications.first?.routing.panelID)
        XCTAssertEqual(store.notifications.first?.routing.workspaceSessionID, workspaceSessionID)
        XCTAssertTrue(notifier.deliveries.isEmpty)
    }

    @MainActor
    func testNotificationStoreRequestsSystemDeliveryOnlyForPolicyDelivery() {
        let notifier = RecordingSystemNotifier()
        let store = NotificationStore(systemNotifier: notifier)
        let completed = agentNotification(kind: .completed, message: "Done")
        let permission = agentNotification(kind: .permissionRequested, message: "Needs approval")
        let failed = agentNotification(kind: .failed, message: "Failed")
        let acknowledgedCompleted = agentNotification(
            kind: .completed,
            message: "Already done",
            acknowledgedAt: Date(timeIntervalSince1970: 20)
        )

        store.ingest(completed)
        store.ingest(permission)
        store.ingest(failed)
        store.ingest(acknowledgedCompleted)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [
            completed.id.uuidString,
            permission.id.uuidString
        ])
        XCTAssertEqual(notifier.deliveries.map(\.body), ["Done", "Needs approval"])
    }

    @MainActor
    func testNotificationStoreDoesNotDeliverSameNotificationIDMoreThanOnce() {
        let notificationID = AgentNotification.ID()
        let notifier = RecordingSystemNotifier()
        let store = NotificationStore(systemNotifier: notifier)
        let original = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Done"
        )
        let updated = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Done again"
        )

        store.ingest(original)
        store.ingest(updated)
        store.acknowledge(id: notificationID)
        store.ingest(updated)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [notificationID.uuidString])
        XCTAssertEqual(store.notifications.count, 1)
        XCTAssertEqual(store.notifications.first?.message, "Done again")
        XCTAssertNotNil(store.notifications.first?.acknowledgedAt)
    }

    @MainActor
    func testNotificationStoreSuppressesDuplicateSystemDeliveryWhileInFlight() {
        let notificationID = AgentNotification.ID()
        let notifier = RecordingSystemNotifier()
        notifier.automaticallyCompletesDeliveries = false
        let store = NotificationStore(systemNotifier: notifier)
        let original = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Done"
        )
        let updated = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Done again"
        )

        store.ingest(original)
        store.ingest(updated)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [notificationID.uuidString])

        notifier.completeDelivery(with: .success(()))
        store.ingest(updated)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [notificationID.uuidString])
    }

    @MainActor
    func testNotificationStoreRetriesSystemDeliveryAfterFailure() {
        let notificationID = AgentNotification.ID()
        let notifier = RecordingSystemNotifier()
        notifier.deliveryResults = [
            .failure(RecordingSystemNotifier.TestError.deliveryFailed),
            .success(())
        ]
        let store = NotificationStore(systemNotifier: notifier)
        let notification = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Done"
        )

        store.ingest(notification)
        store.ingest(notification)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [
            notificationID.uuidString,
            notificationID.uuidString
        ])
    }

    @MainActor
    func testNotificationStoreRetriesSystemDeliveryAfterAsyncFailure() {
        let notificationID = AgentNotification.ID()
        let notifier = RecordingSystemNotifier()
        notifier.automaticallyCompletesDeliveries = false
        let store = NotificationStore(systemNotifier: notifier)
        let notification = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Done"
        )

        store.ingest(notification)
        store.ingest(notification)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [notificationID.uuidString])

        notifier.completeDelivery(with: .failure(RecordingSystemNotifier.TestError.deliveryFailed))
        store.ingest(notification)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [
            notificationID.uuidString,
            notificationID.uuidString
        ])
    }

    @MainActor
    func testNotificationStoreSuppressesDuplicateSystemDeliveryWhileInFlightAfterPrune() {
        let notificationID = AgentNotification.ID()
        let prunedNotification = agentNotification(
            id: notificationID,
            kind: .completed,
            message: "Pruned"
        )
        let retainedNotification = agentNotification(
            kind: .completed,
            message: "Retained"
        )
        let notifier = RecordingSystemNotifier()
        notifier.automaticallyCompletesDeliveries = false
        let store = NotificationStore(
            systemNotifier: notifier,
            maximumNotificationHistoryCount: 1
        )

        store.ingest(prunedNotification)
        store.ingest(retainedNotification)
        store.ingest(prunedNotification)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [
            notificationID.uuidString,
            retainedNotification.id.uuidString
        ])

        notifier.completeDelivery(with: .failure(RecordingSystemNotifier.TestError.deliveryFailed))
        store.ingest(prunedNotification)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [
            notificationID.uuidString,
            retainedNotification.id.uuidString,
            notificationID.uuidString
        ])
    }

    @MainActor
    func testNotificationStorePrunesNotificationsAndDeliveryStateToHistoryBound() {
        let first = agentNotification(kind: .completed, message: "First")
        let second = agentNotification(kind: .completed, message: "Second")
        let third = agentNotification(kind: .completed, message: "Third")
        let notifier = RecordingSystemNotifier()
        let store = NotificationStore(
            systemNotifier: notifier,
            maximumNotificationHistoryCount: 2
        )

        store.ingest(first)
        store.ingest(second)
        store.ingest(third)
        store.ingest(second)
        store.ingest(first)

        XCTAssertEqual(notifier.deliveries.map(\.identifier), [
            first.id.uuidString,
            second.id.uuidString,
            third.id.uuidString,
            first.id.uuidString
        ])
        XCTAssertEqual(store.notifications.map(\.id), [first.id, third.id])
    }

    @MainActor
    func testNotificationStoreAcknowledgeClearsBadgesAndCanHideFromRail() {
        let panelID = PanelNode.ID()
        let acknowledgedAt = Date(timeIntervalSince1970: 30)
        let store = NotificationStore(clock: { acknowledgedAt })
        let notification = agentNotification(panelID: panelID, kind: .permissionRequested)

        store.ingest(notification)
        store.acknowledge(id: notification.id)

        XCTAssertEqual(store.notifications.first?.acknowledgedAt, acknowledgedAt)
        XCTAssertFalse(store.notifications.first?.routing.shouldShowInLeftRail ?? true)
        XCTAssertFalse(store.notifications.first?.routing.shouldBadgePanel ?? true)
        XCTAssertEqual(store.notifications.first?.routing.panelID, panelID)
        XCTAssertNil(store.notifications.first?.routing.workspaceSessionID)
    }

    @MainActor
    func testNotificationStoreReroutesExistingNotificationsWhenPolicyChanges() {
        let store = NotificationStore(
            policy: NotificationRoutingPolicy(showsAcknowledged: false, minimumLevel: .info)
        )
        let visibleNotification = agentNotification(
            level: .info,
            kind: .waitingForInput,
            message: "Waiting"
        )

        store.ingest(visibleNotification)
        XCTAssertTrue(store.notifications.first?.routing.shouldShowInLeftRail ?? false)

        store.policy = NotificationRoutingPolicy(showsAcknowledged: false, minimumLevel: .warning)

        XCTAssertFalse(store.notifications.first?.routing.shouldShowInLeftRail ?? true)
        XCTAssertFalse(store.notifications.first?.routing.shouldBadgePanel ?? true)
    }

    @MainActor
    func testNotificationStoreFindsMostRecentVisibleNotificationForWorkspace() {
        let workspaceID = Workspace.ID()
        let otherWorkspaceID = Workspace.ID()
        let store = NotificationStore()
        let oldest = agentNotification(
            workspaceID: workspaceID,
            message: "Oldest",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let otherWorkspaceNewest = agentNotification(
            workspaceID: otherWorkspaceID,
            message: "Other",
            createdAt: Date(timeIntervalSince1970: 5)
        )
        let newestInWorkspace = agentNotification(
            workspaceID: workspaceID,
            message: "Newest",
            createdAt: Date(timeIntervalSince1970: 3)
        )

        store.ingest(oldest)
        store.ingest(otherWorkspaceNewest)
        store.ingest(newestInWorkspace)

        XCTAssertEqual(
            store.mostRecentVisibleNotificationID(workspaceID: workspaceID),
            newestInWorkspace.id
        )
        XCTAssertEqual(
            store.mostRecentVisibleNotificationID(workspaceID: nil),
            otherWorkspaceNewest.id
        )
    }

    @MainActor
    func testNotificationStoreMostRecentVisibleNotificationIgnoresHiddenEntries() {
        let workspaceID = Workspace.ID()
        let store = NotificationStore(
            policy: NotificationRoutingPolicy(showsAcknowledged: false, minimumLevel: .warning)
        )
        let visible = agentNotification(
            workspaceID: workspaceID,
            level: .warning,
            message: "Visible",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let hiddenLowPriority = agentNotification(
            workspaceID: workspaceID,
            level: .info,
            message: "Low priority",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let hiddenAcknowledged = agentNotification(
            workspaceID: workspaceID,
            level: .warning,
            message: "Acknowledged",
            createdAt: Date(timeIntervalSince1970: 3),
            acknowledgedAt: Date(timeIntervalSince1970: 4)
        )

        store.ingest(visible)
        store.ingest(hiddenLowPriority)
        store.ingest(hiddenAcknowledged)

        XCTAssertEqual(
            store.mostRecentVisibleNotificationID(workspaceID: workspaceID),
            visible.id
        )
    }

    @MainActor
    func testNotificationStoreMostRecentVisibleNotificationIgnoresAcknowledgedEvenWhenVisible() {
        let workspaceID = Workspace.ID()
        let store = NotificationStore(
            policy: NotificationRoutingPolicy(showsAcknowledged: true, minimumLevel: .info)
        )
        let visible = agentNotification(
            workspaceID: workspaceID,
            message: "Visible",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let acknowledged = agentNotification(
            workspaceID: workspaceID,
            message: "Acknowledged",
            createdAt: Date(timeIntervalSince1970: 2),
            acknowledgedAt: Date(timeIntervalSince1970: 3)
        )

        store.ingest(visible)
        store.ingest(acknowledged)

        XCTAssertTrue(store.notifications.first?.routing.shouldShowInLeftRail ?? false)
        XCTAssertEqual(
            store.mostRecentVisibleNotificationID(workspaceID: workspaceID),
            visible.id
        )
    }

    private func agentNotification(
        id: AgentNotification.ID = AgentNotification.ID(),
        workspaceID: Workspace.ID = Workspace.ID(),
        panelID: PanelNode.ID? = PanelNode.ID(),
        sessionID: TerminalSession.ID = TerminalSession.ID(),
        workspaceSessionID: WorkspaceSession.ID? = nil,
        level: NotificationLevel = .info,
        kind: AgentNotificationKind = .waitingForInput,
        message: String = "Notification",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        acknowledgedAt: Date? = nil
    ) -> AgentNotification {
        AgentNotification(
            id: id,
            workspaceID: workspaceID,
            panelID: panelID,
            sessionID: sessionID,
            workspaceSessionID: workspaceSessionID,
            level: level,
            kind: kind,
            message: message,
            createdAt: createdAt,
            acknowledgedAt: acknowledgedAt
        )
    }
}

@MainActor
private final class RecordingSystemNotifier: SystemNotificationDelivering {
    enum TestError: Error {
        case deliveryFailed
    }

    private(set) var deliveries: [SystemNotificationDelivery] = []
    var deliveryResults: [Result<Void, any Error>] = []
    var automaticallyCompletesDeliveries = true
    private var deliveryCompletions: [@MainActor (Result<Void, any Error>) -> Void] = []

    func prepare(completionHandler: @escaping @MainActor (Result<Bool, any Error>) -> Void) {
        completionHandler(.success(true))
    }

    func deliver(
        _ delivery: SystemNotificationDelivery,
        completionHandler: @escaping @MainActor (Result<Void, any Error>) -> Void
    ) {
        deliveries.append(delivery)
        if automaticallyCompletesDeliveries {
            completionHandler(deliveryResults.isEmpty ? .success(()) : deliveryResults.removeFirst())
        } else {
            deliveryCompletions.append(completionHandler)
        }
    }

    func completeDelivery(
        at index: Int = 0,
        with result: Result<Void, any Error>
    ) {
        deliveryCompletions.remove(at: index)(result)
    }
}
