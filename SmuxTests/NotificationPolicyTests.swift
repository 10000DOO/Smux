import XCTest
@testable import Smux

final class NotificationPolicyTests: XCTestCase {
    func testRoutingPolicyFiltersByMinimumLevelAndAcknowledgement() {
        let panelID = PanelNode.ID()
        let workspaceSessionID = WorkspaceSession.ID()
        let policy = NotificationRoutingPolicy(showsAcknowledged: false, minimumLevel: .warning)

        let lowPriorityRoute = policy.route(
            agentNotification(
                panelID: panelID,
                workspaceSessionID: workspaceSessionID,
                level: .info
            )
        )
        XCTAssertFalse(lowPriorityRoute.shouldShowInLeftRail)
        XCTAssertFalse(lowPriorityRoute.shouldBadgePanel)
        XCTAssertEqual(lowPriorityRoute.panelID, panelID)
        XCTAssertEqual(lowPriorityRoute.workspaceSessionID, workspaceSessionID)

        let visibleRoute = policy.route(
            agentNotification(
                panelID: panelID,
                workspaceSessionID: workspaceSessionID,
                level: .warning
            )
        )
        XCTAssertTrue(visibleRoute.shouldShowInLeftRail)
        XCTAssertTrue(visibleRoute.shouldBadgePanel)

        let acknowledgedRoute = policy.route(
            agentNotification(
                panelID: panelID,
                level: .critical,
                acknowledgedAt: Date(timeIntervalSince1970: 10)
            )
        )
        XCTAssertFalse(acknowledgedRoute.shouldShowInLeftRail)
        XCTAssertFalse(acknowledgedRoute.shouldBadgePanel)
    }

    func testRoutingPolicyCanShowAcknowledgedWithoutPanelBadge() {
        let panelID = PanelNode.ID()
        let policy = NotificationRoutingPolicy(showsAcknowledged: true, minimumLevel: .info)

        let route = policy.route(
            agentNotification(
                panelID: panelID,
                level: .error,
                acknowledgedAt: Date(timeIntervalSince1970: 10)
            )
        )

        XCTAssertTrue(route.shouldShowInLeftRail)
        XCTAssertFalse(route.shouldBadgePanel)
        XCTAssertEqual(route.panelID, panelID)
    }

    func testRoutingPolicyAllowsSystemDeliveryForEligibleKinds() {
        let completed = agentNotification(kind: .completed, message: "Done")
        let permission = agentNotification(kind: .permissionRequested, message: "Needs approval")
        let policy = NotificationRoutingPolicy.default

        XCTAssertTrue(policy.allowsSystemDelivery(for: completed))
        XCTAssertTrue(policy.allowsSystemDelivery(for: permission))
    }

    func testRoutingPolicyDisallowsSystemDeliveryWhenDisabledAcknowledgedOrIneligible() {
        let disabledPolicy = NotificationRoutingPolicy(sendsSystemNotifications: false)
        let defaultPolicy = NotificationRoutingPolicy.default

        XCTAssertFalse(disabledPolicy.allowsSystemDelivery(for: agentNotification(kind: .completed)))
        XCTAssertFalse(
            defaultPolicy.allowsSystemDelivery(
                for: agentNotification(kind: .completed, acknowledgedAt: Date(timeIntervalSince1970: 20))
            )
        )
        XCTAssertFalse(defaultPolicy.allowsSystemDelivery(for: agentNotification(kind: .failed)))
        XCTAssertFalse(defaultPolicy.allowsSystemDelivery(for: agentNotification(kind: .waitingForInput)))
    }

    func testRoutingPolicyRoutesFromPrimitiveNotificationFields() {
        let panelID = PanelNode.ID()
        let workspaceSessionID = WorkspaceSession.ID()
        let policy = NotificationRoutingPolicy(showsAcknowledged: false, minimumLevel: .warning)

        let route = policy.route(
            panelID: panelID,
            workspaceSessionID: workspaceSessionID,
            level: .critical,
            acknowledgedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertFalse(route.shouldShowInLeftRail)
        XCTAssertFalse(route.shouldBadgePanel)
        XCTAssertEqual(route.panelID, panelID)
        XCTAssertEqual(route.workspaceSessionID, workspaceSessionID)
    }

    func testDeliveryFactoryCreatesSystemDeliveryPayload() {
        let notification = agentNotification(
            kind: .permissionRequested,
            message: "Needs approval"
        )

        let delivery = SystemNotificationDeliveryFactory.default.delivery(for: notification)

        XCTAssertEqual(delivery.identifier, notification.id.uuidString)
        XCTAssertEqual(delivery.title, "Smux needs approval")
        XCTAssertEqual(delivery.body, "Needs approval")
        XCTAssertEqual(delivery.interruption, .active)
        XCTAssertEqual(delivery.userInfo["workspaceNotificationID"], notification.id.uuidString)
        XCTAssertEqual(delivery.userInfo["workspaceID"], notification.workspaceID.uuidString)
        XCTAssertEqual(delivery.userInfo["sessionID"], notification.sessionID.uuidString)
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
            createdAt: Date(timeIntervalSince1970: 1),
            acknowledgedAt: acknowledgedAt
        )
    }
}
