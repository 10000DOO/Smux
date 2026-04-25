import XCTest
@testable import Smux

final class AgentStateTerminalOutputMonitorTests: XCTestCase {
    @MainActor
    func testDuplicateTransitionDoesNotCreateDuplicateNotification() {
        let stateStore = AgentStateStore()
        let notificationStore = NotificationStore()
        let monitor = AgentTerminalOutputMonitor(
            stateStore: stateStore,
            notificationStore: notificationStore
        )
        let sessionID = TerminalSession.ID()
        let workspaceID = Workspace.ID()
        let panelID = PanelNode.ID()

        let first = monitor.ingest(
            output: "Codex\nDo you want to allow this command?",
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )
        let duplicate = monitor.ingest(
            output: "Do you want to allow this command?",
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )

        XCTAssertNotNil(first)
        XCTAssertNil(duplicate)
        XCTAssertEqual(stateStore.transitions.count, 1)
        XCTAssertEqual(notificationStore.notifications.count, 1)
        XCTAssertEqual(notificationStore.notifications.first?.id, first?.id)
    }

    @MainActor
    func testPermissionRequestCreatesWarningPermissionNotification() {
        let notificationStore = NotificationStore()
        let monitor = AgentTerminalOutputMonitor(
            stateStore: AgentStateStore(),
            notificationStore: notificationStore
        )
        let sessionID = TerminalSession.ID()
        let workspaceID = Workspace.ID()
        let panelID = PanelNode.ID()

        let notification = monitor.ingest(
            output: Data("Codex\nDo you want to allow this command?".utf8),
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )

        XCTAssertEqual(notification?.workspaceID, workspaceID)
        XCTAssertEqual(notification?.panelID, panelID)
        XCTAssertEqual(notification?.sessionID, sessionID)
        XCTAssertEqual(notification?.kind, .permissionRequested)
        XCTAssertEqual(notification?.level, .warning)
        XCTAssertEqual(notification?.message, "Do you want to allow this command?")
        XCTAssertEqual(notificationStore.notifications.first?.source, .agent(notification?.id ?? UUID()))
        XCTAssertEqual(notificationStore.notifications.first?.level, .warning)
    }

    @MainActor
    func testCompletedCreatesInfoCompletedNotification() {
        let notificationStore = NotificationStore()
        let monitor = AgentTerminalOutputMonitor(
            stateStore: AgentStateStore(),
            notificationStore: notificationStore
        )
        let sessionID = TerminalSession.ID()
        let workspaceID = Workspace.ID()

        let notification = monitor.ingest(
            output: "Codex completed successfully",
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: nil
        )

        XCTAssertEqual(notification?.workspaceID, workspaceID)
        XCTAssertNil(notification?.panelID)
        XCTAssertEqual(notification?.sessionID, sessionID)
        XCTAssertEqual(notification?.kind, .completed)
        XCTAssertEqual(notification?.level, .info)
        XCTAssertEqual(notification?.message, "Codex completed successfully")
        XCTAssertEqual(notificationStore.notifications.first?.source, .agent(notification?.id ?? UUID()))
        XCTAssertEqual(notificationStore.notifications.first?.level, .info)
        XCTAssertNil(notificationStore.notifications.first?.routing.panelID)
    }
}
