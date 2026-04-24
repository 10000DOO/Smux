import XCTest
@testable import Smux

final class WorkspacePanelFoundationTests: XCTestCase {
    func testPanelNodeFactoryMaintainsLeafAndSplitShape() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let terminalID = UUID()
        let previewID = UUID()

        let first = PanelNode.leaf(id: firstPanelID, surface: .terminal(sessionID: terminalID))
        let second = PanelNode.leaf(id: secondPanelID, surface: .preview(previewID: previewID))
        let split = PanelNode.split(direction: .horizontal, ratio: 1.2, first: first, second: second)

        XCTAssertTrue(first.isLeaf)
        XCTAssertNil(first.direction)
        XCTAssertNil(first.ratio)
        XCTAssertTrue(first.children.isEmpty)
        XCTAssertEqual(first.surface, .terminal(sessionID: terminalID))

        XCTAssertTrue(split.isSplit)
        XCTAssertEqual(split.direction, .horizontal)
        XCTAssertEqual(split.children.count, 2)
        XCTAssertNil(split.surface)
        XCTAssertEqual(split.normalizedRatio, 0.9)
        XCTAssertEqual(split.firstLeafID, firstPanelID)
    }

    func testPanelNodeFactoryClampsLowRatioAndLimitsSplitChildren() {
        let first = PanelNode.leaf(surface: .empty)
        let second = PanelNode.leaf(surface: .empty)
        let third = PanelNode.leaf(surface: .empty)
        let split = PanelNode(
            kind: .split,
            direction: .vertical,
            ratio: -1,
            children: [first, second, third],
            surface: .terminal(sessionID: UUID())
        )

        XCTAssertEqual(split.normalizedRatio, 0.1)
        XCTAssertEqual(split.children.count, 2)
        XCTAssertNil(split.surface)
    }

    func testPanelNodeReplacementIgnoresSplitNodeTarget() {
        let splitID = UUID()
        let first = PanelNode.leaf(surface: .empty)
        let second = PanelNode.leaf(surface: .empty)
        let split = PanelNode.split(
            id: splitID,
            direction: .horizontal,
            first: first,
            second: second
        )

        let replaced = split.replacingSurface(
            panelID: splitID,
            with: .terminal(sessionID: UUID())
        )

        XCTAssertEqual(replaced, split)
    }

    @MainActor
    func testPanelStoreSplitsFocusedPanelAndFocusesNewLeaf() {
        let rootID = UUID()
        let editorID = UUID()
        let store = PanelStore(rootNode: .leaf(id: rootID, surface: .empty))

        store.splitFocusedPanel(direction: .vertical, surface: .editor(documentID: editorID))

        XCTAssertTrue(store.rootNode.isSplit)
        XCTAssertEqual(store.rootNode.direction, .vertical)
        XCTAssertEqual(store.rootNode.children.count, 2)
        XCTAssertEqual(store.rootNode.children.first?.id, rootID)
        XCTAssertEqual(store.rootNode.children.last?.surface, .editor(documentID: editorID))
        XCTAssertEqual(store.focusedPanelID, store.rootNode.children.last?.id)
    }

    @MainActor
    func testPanelStoreReplacesFocusedPanelSurface() {
        let rootID = UUID()
        let terminalID = UUID()
        let store = PanelStore(rootNode: .leaf(id: rootID, surface: .empty))

        store.replaceFocusedPanel(with: .terminal(sessionID: terminalID))

        XCTAssertEqual(store.rootNode.id, rootID)
        XCTAssertEqual(store.rootNode.surface, .terminal(sessionID: terminalID))
        XCTAssertEqual(store.focusedPanelID, rootID)
    }

    @MainActor
    func testPanelStoreIgnoresUnknownFocusAndKeepsCurrentPanel() {
        let rootID = UUID()
        let store = PanelStore(rootNode: .leaf(id: rootID, surface: .empty))

        store.focus(panelID: UUID())

        XCTAssertEqual(store.focusedPanelID, rootID)
    }

    @MainActor
    func testPanelStoreDoesNotFocusOrReplaceSplitNodes() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let splitID = UUID()
        let terminalID = UUID()
        let split = PanelNode.split(
            id: splitID,
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore(rootNode: split)

        store.focus(panelID: splitID)
        store.replaceFocusedPanel(with: .terminal(sessionID: terminalID))

        XCTAssertEqual(store.focusedPanelID, firstPanelID)
        XCTAssertEqual(store.rootNode.kind, .split)
        XCTAssertEqual(store.rootNode.children.first?.surface, .terminal(sessionID: terminalID))
    }

    @MainActor
    func testPanelStoreResetMovesFocusToFirstLeaf() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let split = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore()

        store.reset(to: split)

        XCTAssertEqual(store.focusedPanelID, firstPanelID)
        XCTAssertEqual(store.rootNode, split)
    }

    @MainActor
    func testWorkspaceStoreSelectsAndClosesWorkspaces() {
        let first = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/SmuxFirst"),
            openedAt: Date(timeIntervalSince1970: 1)
        )
        let second = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/SmuxSecond"),
            openedAt: Date(timeIntervalSince1970: 2)
        )
        let store = WorkspaceStore(activeWorkspace: first, workspaces: [first, second])

        store.selectWorkspace(id: second.id)
        XCTAssertEqual(store.activeWorkspace?.id, second.id)

        store.closeWorkspace(id: second.id)
        XCTAssertEqual(store.activeWorkspace?.id, first.id)
        XCTAssertEqual(store.workspaces.map(\.id), [first.id])
    }

    @MainActor
    func testWorkspaceStoreAddsInitialActiveWorkspaceWhenMissing() {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/SmuxOnly")
        )
        let store = WorkspaceStore(activeWorkspace: workspace)

        XCTAssertEqual(store.activeWorkspace?.id, workspace.id)
        XCTAssertEqual(store.workspaces.map(\.id), [workspace.id])
    }

    @MainActor
    func testWorkspaceStoreUpsertReplacesWithoutDuplicates() {
        let workspaceID = UUID()
        let original = Workspace.make(
            id: workspaceID,
            rootURL: URL(fileURLWithPath: "/tmp/Original")
        )
        let updated = Workspace.make(
            id: workspaceID,
            rootURL: URL(fileURLWithPath: "/tmp/Updated"),
            displayName: "Updated"
        )
        let store = WorkspaceStore(workspaces: [original])

        store.upsertWorkspace(updated)

        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.workspaces.first?.displayName, "Updated")
    }

    @MainActor
    func testWorkspaceStoreUnknownSelectionIsNoOp() {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/SmuxKnown")
        )
        let store = WorkspaceStore(activeWorkspace: workspace, workspaces: [workspace])

        store.selectWorkspace(id: UUID())

        XCTAssertEqual(store.activeWorkspace?.id, workspace.id)
    }

    @MainActor
    func testWorkspaceStoreCloseInactiveWorkspaceKeepsActive() {
        let active = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/Active")
        )
        let inactive = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/Inactive")
        )
        let store = WorkspaceStore(activeWorkspace: active, workspaces: [active, inactive])

        store.closeWorkspace(id: inactive.id)

        XCTAssertEqual(store.activeWorkspace?.id, active.id)
        XCTAssertEqual(store.workspaces.map(\.id), [active.id])
    }

    @MainActor
    func testWorkspaceStoreCloseLastWorkspaceClearsActive() {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/Last")
        )
        let store = WorkspaceStore(activeWorkspace: workspace, workspaces: [workspace])

        store.closeWorkspace(id: workspace.id)

        XCTAssertNil(store.activeWorkspace)
        XCTAssertTrue(store.workspaces.isEmpty)
    }

    @MainActor
    func testWorkspaceStoreClearOpenError() {
        let store = WorkspaceStore()
        store.openErrorMessage = "Failed"

        store.clearOpenError()

        XCTAssertNil(store.openErrorMessage)
    }

    func testWorkspaceSnapshotRoundTripsPanelTreeAndSurfaceDescriptors() throws {
        let workspaceID = UUID()
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let terminalID = UUID()
        let documentID = UUID()
        let workspace = Workspace.make(
            id: workspaceID,
            rootURL: URL(fileURLWithPath: "/tmp/SmuxWorkspace"),
            panelRootID: firstPanelID,
            openedAt: Date(timeIntervalSince1970: 10)
        )
        let panelTree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .terminal(sessionID: terminalID)),
            second: .leaf(id: secondPanelID, surface: .editor(documentID: documentID))
        )
        let snapshot = WorkspaceSnapshot(workspace: workspace, panelTree: panelTree)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, WorkspaceSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.workspaceID, workspaceID)
        XCTAssertEqual(decoded.panelTree, panelTree)
        XCTAssertEqual(decoded.leftRailState.selectedWorkspaceID, workspaceID)
        XCTAssertEqual(decoded.leftRailState.selectedPanelID, firstPanelID)
        XCTAssertTrue(decoded.leftRailState.isFileTreeVisible)
    }

    func testWorkspaceSnapshotUsesCustomLeftRailState() {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/CustomRail")
        )
        let panelTree = PanelNode.leaf(surface: .empty)
        let leftRailState = LeftRailState(
            selectedWorkspaceID: nil,
            selectedPanelID: nil,
            isFileTreeVisible: false
        )

        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            panelTree: panelTree,
            leftRailState: leftRailState
        )

        XCTAssertEqual(snapshot.leftRailState, leftRailState)
    }

    func testWorkspaceSnapshotWithoutPanelTreeHasNoSelectedPanel() {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/NoPanel")
        )

        let snapshot = WorkspaceSnapshot(workspace: workspace, panelTree: nil)

        XCTAssertNil(snapshot.panelTree)
        XCTAssertNil(snapshot.leftRailState.selectedPanelID)
        XCTAssertEqual(snapshot.leftRailState.selectedWorkspaceID, workspace.id)
    }
}
