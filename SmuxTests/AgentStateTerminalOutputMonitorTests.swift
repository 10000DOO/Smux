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
        let workspaceSessionID = WorkspaceSession.ID()
        let workspaceID = Workspace.ID()
        let panelID = PanelNode.ID()

        let notification = monitor.ingest(
            output: Data("Codex\nDo you want to allow this command?".utf8),
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID,
            workspaceSessionID: workspaceSessionID
        )

        XCTAssertEqual(notification?.workspaceID, workspaceID)
        XCTAssertEqual(notification?.panelID, panelID)
        XCTAssertEqual(notification?.sessionID, sessionID)
        XCTAssertEqual(notification?.workspaceSessionID, workspaceSessionID)
        XCTAssertEqual(notification?.kind, .permissionRequested)
        XCTAssertEqual(notification?.level, .warning)
        XCTAssertEqual(notification?.message, "Do you want to allow this command?")
        XCTAssertEqual(notificationStore.notifications.first?.source, .agent(notification?.id ?? UUID()))
        XCTAssertEqual(notificationStore.notifications.first?.level, .warning)
        XCTAssertEqual(notificationStore.notifications.first?.routing.workspaceSessionID, workspaceSessionID)
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

    @MainActor
    func testHookPayloadCreatesNotification() {
        let notificationStore = NotificationStore()
        let monitor = AgentTerminalOutputMonitor(
            stateStore: AgentStateStore(),
            notificationStore: notificationStore
        )
        let sessionID = TerminalSession.ID()
        let workspaceID = Workspace.ID()
        let panelID = PanelNode.ID()

        let notification = monitor.ingest(
            hookPayload: AgentHookPayload(
                agentKind: .claude,
                eventName: "Notification",
                body: "Please respond before continuing."
            ),
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )

        XCTAssertEqual(notification?.workspaceID, workspaceID)
        XCTAssertEqual(notification?.panelID, panelID)
        XCTAssertEqual(notification?.sessionID, sessionID)
        XCTAssertEqual(notification?.kind, .waitingForInput)
        XCTAssertEqual(notification?.level, .warning)
        XCTAssertEqual(notification?.message, "Please respond before continuing.")
        XCTAssertEqual(notificationStore.notifications.first?.agentKind, .waitingForInput)
        XCTAssertEqual(notificationStore.notifications.first?.routing.panelID, panelID)
    }

    @MainActor
    func testHookPayloadDuplicateOfTerminalOutputDoesNotCreateDuplicateNotification() {
        let stateStore = AgentStateStore()
        let notificationStore = NotificationStore()
        let monitor = AgentTerminalOutputMonitor(
            stateStore: stateStore,
            notificationStore: notificationStore
        )
        let sessionID = TerminalSession.ID()
        let workspaceID = Workspace.ID()
        let panelID = PanelNode.ID()

        let terminalNotification = monitor.ingest(
            output: "Codex\nDo you want to allow this command?",
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )
        let hookNotification = monitor.ingest(
            hookPayload: AgentHookPayload(
                agentKind: .codex,
                eventName: "PermissionRequest",
                body: "Do you want to allow this command?"
            ),
            sessionID: sessionID,
            workspaceID: workspaceID,
            panelID: panelID
        )

        XCTAssertNotNil(terminalNotification)
        XCTAssertNil(hookNotification)
        XCTAssertEqual(stateStore.transitions.count, 1)
        XCTAssertEqual(notificationStore.notifications.count, 1)
    }
}
