import XCTest
@testable import Smux

final class WorkspaceShellTests: XCTestCase {
    func testPanelSurfacePresentationForFeatureSurfaces() {
        let terminal = PanelSurfacePresentation(
            surface: .terminal(sessionID: UUID())
        )
        let editor = PanelSurfacePresentation(
            surface: .editor(documentID: UUID())
        )
        let preview = PanelSurfacePresentation(
            surface: .preview(previewID: UUID())
        )

        XCTAssertEqual(terminal.title, "Terminal")
        XCTAssertEqual(terminal.systemImage, "terminal")
        XCTAssertEqual(terminal.accessibilityLabel, "Terminal panel surface")

        XCTAssertEqual(editor.title, "Editor")
        XCTAssertEqual(editor.systemImage, "doc.text")
        XCTAssertEqual(editor.accessibilityLabel, "Editor panel surface")

        XCTAssertEqual(preview.title, "Preview")
        XCTAssertEqual(preview.systemImage, "eye")
        XCTAssertEqual(preview.accessibilityLabel, "Preview panel surface")
    }

    func testPanelSurfacePresentationForEmptySurface() {
        let presentation = PanelSurfacePresentation(surface: .empty)

        XCTAssertEqual(presentation.title, "Workspace")
        XCTAssertEqual(presentation.systemImage, "rectangle.split.3x1")
        XCTAssertEqual(presentation.accessibilityLabel, "Workspace panel surface")
    }

    func testPanelNodeLeafSummariesPreserveTreeOrderAndFocus() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let terminalID = UUID()
        let previewID = UUID()
        let tree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .terminal(sessionID: terminalID)),
            second: .leaf(id: secondPanelID, surface: .preview(previewID: previewID))
        )

        let summaries = tree.leafSummaries(focusedPanelID: secondPanelID)

        XCTAssertEqual(summaries.map(\.id), [firstPanelID, secondPanelID])
        XCTAssertEqual(summaries.map(\.surface), [
            .terminal(sessionID: terminalID),
            .preview(previewID: previewID)
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
            with: .terminal(sessionID: terminalID)
        )

        XCTAssertEqual(store.focusedPanelID, secondPanelID)
        XCTAssertEqual(store.rootNode.children.first?.surface, .empty)
        XCTAssertEqual(
            store.rootNode.children.last?.surface,
            .terminal(sessionID: terminalID)
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
        shouldBadgePanel: Bool,
        acknowledgedAt: Date? = nil
    ) -> WorkspaceNotification {
        WorkspaceNotification(
            id: UUID(),
            workspaceID: workspaceID,
            source: .system,
            level: .warning,
            message: "Notification",
            routing: WorkspaceNotificationRouting(
                panelID: panelID,
                shouldShowInLeftRail: true,
                shouldBadgePanel: shouldBadgePanel
            ),
            acknowledgedAt: acknowledgedAt
        )
    }
}
