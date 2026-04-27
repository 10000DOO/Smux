import XCTest
@testable import Smux

final class WorkspaceShellTests: XCTestCase {
    func testPanelSurfacePresentationForFeatureSurfaces() {
        let terminal = PanelSurfacePresentation(
            session: WorkspaceSession(
                id: WorkspaceSession.ID(),
                workspaceID: Workspace.ID(),
                kind: .terminal,
                content: .terminal(TerminalSession.ID()),
                title: "Terminal",
                createdAt: Date(timeIntervalSince1970: 0)
            )
        )
        let editor = PanelSurfacePresentation(
            session: WorkspaceSession(
                id: WorkspaceSession.ID(),
                workspaceID: Workspace.ID(),
                kind: .editor,
                content: .editor(DocumentSession.ID()),
                title: "Editor",
                createdAt: Date(timeIntervalSince1970: 0)
            )
        )
        let preview = PanelSurfacePresentation(
            session: WorkspaceSession(
                id: WorkspaceSession.ID(),
                workspaceID: Workspace.ID(),
                kind: .preview,
                content: .preview(
                    previewID: PreviewState.ID(),
                    sourceDocumentID: DocumentSession.ID()
                ),
                title: "Preview",
                createdAt: Date(timeIntervalSince1970: 0)
            )
        )

        XCTAssertEqual(terminal.title, "Terminal")
        XCTAssertEqual(terminal.systemImage, "terminal")
        XCTAssertEqual(terminal.accessibilityLabel, "Terminal session")

        XCTAssertEqual(editor.title, "Editor")
        XCTAssertEqual(editor.systemImage, "doc.text")
        XCTAssertEqual(editor.accessibilityLabel, "Editor session")

        XCTAssertEqual(preview.title, "Preview")
        XCTAssertEqual(preview.systemImage, "eye")
        XCTAssertEqual(preview.accessibilityLabel, "Preview session")
    }

    func testPanelSurfacePresentationForEmptySurface() {
        let presentation = PanelSurfacePresentation(surface: .empty)

        XCTAssertEqual(presentation.title, "New Panel")
        XCTAssertEqual(presentation.systemImage, "plus.square")
        XCTAssertEqual(presentation.accessibilityLabel, "New Panel surface")
    }

    func testPanelStartSurfacePrimaryOptionsPrioritizeContentChoices() {
        let options = PanelStartSurfaceOptionPresentation.primaryOptions(
            hasSelectedDocument: true
        )

        XCTAssertEqual(options.map(\.destination), [.terminal, .editor, .preview])
        XCTAssertEqual(options.map(\.title), ["Terminal", "Editor", "Preview"])
        XCTAssertEqual(options.map(\.isEnabled), [true, true, true])
    }

    func testPanelStartSurfaceDocumentChoicesRequireSelectedDocument() {
        let options = PanelStartSurfaceOptionPresentation.primaryOptions(
            hasSelectedDocument: false
        )

        XCTAssertEqual(options.map(\.destination), [.terminal, .editor, .preview])
        XCTAssertEqual(options.map(\.isEnabled), [true, false, false])
    }

    func testPanelNodeLeafSummariesPreserveTreeOrderAndFocus() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let terminalID = UUID()
        let previewID = UUID()
        let tree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .session(sessionID: terminalID)),
            second: .leaf(id: secondPanelID, surface: .session(sessionID: previewID))
        )

        let summaries = tree.leafSummaries(focusedPanelID: secondPanelID)

        XCTAssertEqual(summaries.map(\.id), [firstPanelID, secondPanelID])
        XCTAssertEqual(summaries.map(\.surface), [
            .session(sessionID: terminalID),
            .session(sessionID: previewID)
        ])
        XCTAssertEqual(summaries.map(\.isFocused), [false, true])
        XCTAssertEqual(tree.leafCount, 2)
    }

    func testPanelNodeLeafSummaryDefaultsMissingSurfaceToWorkspace() {
        let panelID = UUID()
        let node = PanelNode(id: panelID, kind: .leaf)

        let summaries = node.leafSummaries(focusedPanelID: panelID)

        XCTAssertEqual(summaries, [
            PanelLeafSummary(id: panelID, surface: .empty, isFocused: true)
        ])
    }

    func testPanelNotificationBadgeSummaryCountsOnlyUnacknowledgedPanelBadges() {
        let panelID = PanelNode.ID()
        let otherPanelID = PanelNode.ID()
        let workspaceID = Workspace.ID()
        let notifications = [
            workspaceNotification(workspaceID: workspaceID, panelID: panelID, shouldBadgePanel: true),
            workspaceNotification(workspaceID: workspaceID, panelID: panelID, shouldBadgePanel: true),
            workspaceNotification(workspaceID: workspaceID, panelID: panelID, shouldBadgePanel: false),
            workspaceNotification(workspaceID: workspaceID, panelID: otherPanelID, shouldBadgePanel: true),
            workspaceNotification(workspaceID: workspaceID, panelID: nil, shouldBadgePanel: false),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                acknowledgedAt: Date(timeIntervalSince1970: 1)
            )
        ]

        XCTAssertEqual(
            PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
                for: panelID,
                notifications: notifications
            ),
            2
        )
    }

    func testPanelNotificationBadgeSummaryCountsWorkspaceSessionBadges() {
        let workspaceID = Workspace.ID()
        let sessionID = WorkspaceSession.ID()
        let otherSessionID = WorkspaceSession.ID()
        let recycledPanelID = PanelNode.ID()
        let notifications = [
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: recycledPanelID,
                workspaceSessionID: sessionID,
                shouldBadgePanel: true
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: recycledPanelID,
                workspaceSessionID: otherSessionID,
                shouldBadgePanel: true
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: recycledPanelID,
                workspaceSessionID: sessionID,
                shouldBadgePanel: true,
                acknowledgedAt: Date(timeIntervalSince1970: 1)
            )
        ]

        XCTAssertEqual(
            PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
                forWorkspaceSession: sessionID,
                notifications: notifications
            ),
            1
        )
        XCTAssertEqual(
            PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
                for: .session(sessionID: sessionID),
                panelID: recycledPanelID,
                notifications: notifications
            ),
            1
        )
    }

    func testLeftRailPanelTabPresentationUsesPanelWorkspaceAndNotifications() {
        let panelID = PanelNode.ID()
        let workspaceID = Workspace.ID()
        let workspace = Workspace.make(
            id: workspaceID,
            rootURL: URL(fileURLWithPath: "/tmp/SmuxWorkspace"),
            gitBranch: "feature/rail"
        )
        let notifications = [
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                message: "Older",
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                message: "Needs attention",
                createdAt: Date(timeIntervalSince1970: 3)
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: PanelNode.ID(),
                shouldBadgePanel: true,
                message: "Other panel",
                createdAt: Date(timeIntervalSince1970: 4)
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                message: "Acknowledged",
                createdAt: Date(timeIntervalSince1970: 5),
                acknowledgedAt: Date(timeIntervalSince1970: 6)
            )
        ]

        let presentation = LeftRailPanelTabPresentation(
            panel: PanelLeafSummary(
                id: panelID,
                surface: .session(sessionID: TerminalSession.ID()),
                isFocused: true
            ),
            session: WorkspaceSession(
                id: WorkspaceSession.ID(),
                workspaceID: workspaceID,
                kind: .terminal,
                content: .terminal(TerminalSession.ID()),
                title: "Terminal",
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            workspace: workspace,
            notifications: notifications
        )

        XCTAssertEqual(presentation.id, panelID)
        XCTAssertEqual(presentation.title, "Terminal")
        XCTAssertEqual(presentation.systemImage, "terminal")
        XCTAssertEqual(presentation.metadataText, "feature/rail - SmuxWorkspace")
        XCTAssertEqual(presentation.latestNotificationMessage, "Needs attention")
        XCTAssertEqual(presentation.badgeCount, 2)
        XCTAssertTrue(presentation.isFocused)
    }

    func testLeftRailSessionPresentationUsesSessionNotifications() {
        let panelID = PanelNode.ID()
        let workspaceID = Workspace.ID()
        let workspace = Workspace.make(
            id: workspaceID,
            rootURL: URL(fileURLWithPath: "/tmp/SessionWorkspace"),
            gitBranch: "feature/sessions"
        )
        let session = WorkspaceSession(
            id: WorkspaceSession.ID(),
            workspaceID: workspaceID,
            kind: .terminal,
            content: .terminal(TerminalSession.ID()),
            title: "Terminal",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let notifications = [
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                workspaceSessionID: session.id,
                shouldBadgePanel: true,
                message: "Older",
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                workspaceSessionID: session.id,
                shouldBadgePanel: true,
                message: "Needs input",
                createdAt: Date(timeIntervalSince1970: 3)
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: panelID,
                workspaceSessionID: WorkspaceSession.ID(),
                shouldBadgePanel: true,
                message: "Reused panel stale badge",
                createdAt: Date(timeIntervalSince1970: 4)
            )
        ]

        let presentation = LeftRailSessionPresentation(
            session: session,
            visiblePanelID: panelID,
            focusedPanelID: panelID,
            workspace: workspace,
            notifications: notifications
        )

        XCTAssertEqual(presentation.id, session.id)
        XCTAssertEqual(presentation.title, "Terminal")
        XCTAssertEqual(presentation.systemImage, "terminal")
        XCTAssertEqual(presentation.metadataText, "feature/sessions - SessionWorkspace")
        XCTAssertEqual(presentation.latestNotificationMessage, "Needs input")
        XCTAssertEqual(presentation.badgeCount, 2)
        XCTAssertTrue(presentation.isFocused)
    }

    func testLeftRailSessionPresentationPreservesHiddenSessionNotifications() {
        let workspaceID = Workspace.ID()
        let session = WorkspaceSession(
            id: WorkspaceSession.ID(),
            workspaceID: workspaceID,
            kind: .terminal,
            content: .terminal(TerminalSession.ID()),
            title: "Terminal",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let presentation = LeftRailSessionPresentation(
            session: session,
            visiblePanelID: nil,
            focusedPanelID: PanelNode.ID(),
            workspace: Workspace.make(id: workspaceID, rootURL: URL(fileURLWithPath: "/tmp/HiddenSessionWorkspace")),
            notifications: [
                workspaceNotification(
                    workspaceID: workspaceID,
                    panelID: PanelNode.ID(),
                    workspaceSessionID: session.id,
                    shouldBadgePanel: true,
                    message: "Hidden session still needs input"
                )
            ]
        )

        XCTAssertEqual(presentation.id, session.id)
        XCTAssertEqual(presentation.latestNotificationMessage, "Hidden session still needs input")
        XCTAssertEqual(presentation.badgeCount, 1)
        XCTAssertFalse(presentation.isFocused)
    }

    func testLeftRailSessionPresentationDoesNotFocusHiddenSessionWhenFocusIsNil() {
        let workspaceID = Workspace.ID()
        let session = WorkspaceSession(
            id: WorkspaceSession.ID(),
            workspaceID: workspaceID,
            kind: .terminal,
            content: .terminal(TerminalSession.ID()),
            title: "Terminal",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let presentation = LeftRailSessionPresentation(
            session: session,
            visiblePanelID: nil,
            focusedPanelID: nil,
            workspace: Workspace.make(id: workspaceID, rootURL: URL(fileURLWithPath: "/tmp/HiddenSessionWorkspace")),
            notifications: []
        )

        XCTAssertFalse(presentation.isFocused)
    }

    func testWorkspaceShellNotificationFilterScopesRailTabsAndPanelBadgesToActiveWorkspace() {
        let panelID = PanelNode.ID()
        let activeWorkspaceID = Workspace.ID()
        let otherWorkspaceID = Workspace.ID()
        let notifications = [
            workspaceNotification(
                workspaceID: activeWorkspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                message: "Active rail",
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            workspaceNotification(
                workspaceID: activeWorkspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                message: "Active badge only",
                createdAt: Date(timeIntervalSince1970: 3),
                shouldShowInLeftRail: false
            ),
            workspaceNotification(
                workspaceID: otherWorkspaceID,
                panelID: panelID,
                shouldBadgePanel: true,
                message: "Other workspace newer",
                createdAt: Date(timeIntervalSince1970: 4)
            )
        ]

        let scopedNotifications = WorkspaceShellNotificationFilter.activeWorkspaceNotifications(
            notifications,
            activeWorkspaceID: activeWorkspaceID
        )
        let railNotifications = WorkspaceShellNotificationFilter.leftRailNotifications(
            from: scopedNotifications
        )
        let presentation = LeftRailPanelTabPresentation(
            panel: PanelLeafSummary(
                id: panelID,
                surface: .session(sessionID: TerminalSession.ID()),
                isFocused: false
            ),
            workspace: nil,
            notifications: scopedNotifications
        )

        XCTAssertEqual(scopedNotifications.map { $0.workspaceID }, [activeWorkspaceID, activeWorkspaceID])
        XCTAssertEqual(railNotifications.map { $0.message }, ["Active rail"])
        XCTAssertEqual(presentation.latestNotificationMessage, "Active rail")
        XCTAssertEqual(presentation.badgeCount, 2)
        XCTAssertEqual(
            PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
                for: panelID,
                notifications: scopedNotifications
            ),
            2
        )
    }

    func testWorkspaceFileOpenPolicyReplacesOnlyEmptyFocusedPanel() {
        XCTAssertEqual(
            WorkspaceFileOpenPolicy.command(focusedSurface: .empty),
            .replaceFocused(.split)
        )
        XCTAssertEqual(
            WorkspaceFileOpenPolicy.command(focusedSurface: .session(sessionID: WorkspaceSession.ID())),
            .openInNewPanel(.split, .horizontal)
        )
        XCTAssertEqual(
            WorkspaceFileOpenPolicy.command(focusedSurface: nil),
            .openInNewPanel(.split, .horizontal)
        )
    }

    @MainActor
    func testLeftRailOpenWorkspaceCallbackCanBeInvoked() {
        var didOpenWorkspace = false
        let view = LeftRailView(onOpenWorkspace: {
            didOpenWorkspace = true
        })

        view.onOpenWorkspace()

        XCTAssertTrue(didOpenWorkspace)
    }

    func testTerminalAutoRefreshTrackerOnlyRefreshesTerminatedSessionOnce() {
        let sessionID = TerminalSession.ID()
        var tracker = TerminalAutoRefreshTracker()

        XCTAssertFalse(tracker.shouldRefresh(sessionID: sessionID, status: .running))
        XCTAssertFalse(tracker.shouldRefresh(sessionID: sessionID, status: .failed))
        XCTAssertTrue(tracker.shouldRefresh(sessionID: sessionID, status: .terminated))
        XCTAssertFalse(tracker.shouldRefresh(sessionID: sessionID, status: .terminated))
        XCTAssertFalse(tracker.shouldRefresh(sessionID: sessionID, status: nil))
        XCTAssertEqual(tracker.refreshedSessionID, sessionID)
    }

    func testLeftRailNotificationSummaryGroupsAgentStatuses() {
        let workspaceID = Workspace.ID()
        let notifications = [
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: PanelNode.ID(),
                shouldBadgePanel: true,
                agentKind: .waitingForInput
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: PanelNode.ID(),
                shouldBadgePanel: true,
                agentKind: .permissionRequested
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: nil,
                shouldBadgePanel: false,
                agentKind: .completed
            ),
            workspaceNotification(
                workspaceID: workspaceID,
                panelID: nil,
                shouldBadgePanel: false,
                agentKind: .failed
            ),
        ]

        let summary = LeftRailNotificationSummary.make(from: notifications)

        XCTAssertEqual(summary.waitingCount, 2)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.items.map(\.title), ["Waiting", "Done", "Failed"])
    }

    func testLeftRailNotificationPresentationUsesAgentKindAndAcknowledgementState() {
        let notification = workspaceNotification(
            workspaceID: Workspace.ID(),
            panelID: PanelNode.ID(),
            shouldBadgePanel: true,
            agentKind: .permissionRequested
        )

        let presentation = LeftRailNotificationPresentation(notification: notification)

        XCTAssertEqual(presentation.title, "Permission")
        XCTAssertEqual(presentation.systemImage, "hand.raised")
        XCTAssertEqual(presentation.message, "Notification")
        XCTAssertTrue(presentation.showsAcknowledge)
    }

    @MainActor
    func testPanelStoreReplacesRequestedPanelWithoutPreFocusing() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let terminalID = UUID()
        let split = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore(rootNode: split)

        store.replacePanel(
            panelID: secondPanelID,
            with: .session(sessionID: terminalID)
        )

        XCTAssertEqual(store.focusedPanelID, secondPanelID)
        XCTAssertEqual(store.rootNode.children.first?.surface, .empty)
        XCTAssertEqual(
            store.rootNode.children.last?.surface,
            .session(sessionID: terminalID)
        )
    }

    @MainActor
    func testPanelStoreSplitsRequestedPanelWithoutPreFocusing() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let split = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore(rootNode: split)

        store.splitPanel(panelID: secondPanelID, direction: .vertical, surface: .empty)

        XCTAssertEqual(store.rootNode.children.first?.id, firstPanelID)
        XCTAssertEqual(store.rootNode.children.last?.kind, .split)
        XCTAssertEqual(store.rootNode.children.last?.direction, .vertical)
        XCTAssertEqual(store.rootNode.children.last?.children.first?.id, secondPanelID)
        XCTAssertEqual(
            store.focusedPanelID,
            store.rootNode.children.last?.children.last?.id
        )
    }

    private func workspaceNotification(
        workspaceID: Workspace.ID,
        panelID: PanelNode.ID?,
        workspaceSessionID: WorkspaceSession.ID? = nil,
        shouldBadgePanel: Bool,
        agentKind: AgentNotificationKind? = nil,
        message: String = "Notification",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        shouldShowInLeftRail: Bool = true,
        acknowledgedAt: Date? = nil
    ) -> WorkspaceNotification {
        WorkspaceNotification(
            id: UUID(),
            workspaceID: workspaceID,
            source: agentKind == nil ? .system : .agent(UUID()),
            level: .warning,
            agentKind: agentKind,
            message: message,
            createdAt: createdAt,
            routing: WorkspaceNotificationRouting(
                panelID: panelID,
                workspaceSessionID: workspaceSessionID,
                shouldShowInLeftRail: shouldShowInLeftRail,
                shouldBadgePanel: shouldBadgePanel
            ),
            acknowledgedAt: acknowledgedAt
        )
    }
}
