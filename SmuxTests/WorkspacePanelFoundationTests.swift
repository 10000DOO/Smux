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

    func testPanelNodeLeafIDsPreserveNestedSplitOrder() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let thirdPanelID = UUID()
        let fourthPanelID = UUID()
        let nested = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .split(
                direction: .vertical,
                first: .leaf(id: secondPanelID, surface: .empty),
                second: .split(
                    direction: .horizontal,
                    first: .leaf(id: thirdPanelID, surface: .empty),
                    second: .leaf(id: fourthPanelID, surface: .empty)
                )
            )
        )

        XCTAssertEqual(nested.leafIDs, [
            firstPanelID,
            secondPanelID,
            thirdPanelID,
            fourthPanelID
        ])
        XCTAssertEqual(nested.firstLeafID, firstPanelID)
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

    func testPanelNodeUpdatesNestedSplitRatioAndClampsValue() {
        let rootSplitID = UUID()
        let nestedSplitID = UUID()
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let thirdPanelID = UUID()
        let tree = PanelNode.split(
            id: rootSplitID,
            direction: .horizontal,
            ratio: 0.4,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .split(
                id: nestedSplitID,
                direction: .vertical,
                ratio: 0.5,
                first: .leaf(id: secondPanelID, surface: .empty),
                second: .leaf(id: thirdPanelID, surface: .empty)
            )
        )

        let updatedTree = tree.updatingSplitRatio(splitID: nestedSplitID, ratio: 1.4)

        XCTAssertEqual(updatedTree?.ratio, 0.4)
        XCTAssertEqual(updatedTree?.children.last?.ratio, 0.9)
        XCTAssertEqual(updatedTree?.leafIDs, [firstPanelID, secondPanelID, thirdPanelID])
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
    func testPanelStoreUpdatesSplitRatioAndIgnoresInvalidTargets() {
        let splitID = UUID()
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let split = PanelNode.split(
            id: splitID,
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore(rootNode: split, focusedPanelID: secondPanelID)

        store.updateSplitRatio(splitID: splitID, ratio: 0.72)
        store.updateSplitRatio(splitID: firstPanelID, ratio: 0.2)
        store.updateSplitRatio(splitID: UUID(), ratio: 0.3)

        XCTAssertEqual(store.rootNode.ratio, 0.72)
        XCTAssertEqual(store.focusedPanelID, secondPanelID)
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
    func testPanelStoreFocusNextAndPreviousKeepSingleLeafFocused() {
        let panelID = UUID()
        let store = PanelStore(rootNode: .leaf(id: panelID, surface: .empty))

        store.focusNextPanel()
        XCTAssertEqual(store.focusedPanelID, panelID)

        store.focusPreviousPanel()
        XCTAssertEqual(store.focusedPanelID, panelID)
    }

    @MainActor
    func testPanelStoreFocusNextAndPreviousFollowNestedLeafOrder() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let thirdPanelID = UUID()
        let tree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .split(
                direction: .vertical,
                first: .leaf(id: secondPanelID, surface: .empty),
                second: .leaf(id: thirdPanelID, surface: .empty)
            )
        )
        let store = PanelStore(rootNode: tree, focusedPanelID: firstPanelID)

        store.focusNextPanel()
        XCTAssertEqual(store.focusedPanelID, secondPanelID)

        store.focusNextPanel()
        XCTAssertEqual(store.focusedPanelID, thirdPanelID)

        store.focusNextPanel()
        XCTAssertEqual(store.focusedPanelID, firstPanelID)

        store.focusPreviousPanel()
        XCTAssertEqual(store.focusedPanelID, thirdPanelID)
    }

    @MainActor
    func testPanelStoreFocusNextAndPreviousRecoverFromNilFocus() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let tree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore(rootNode: tree)

        store.focus(panelID: nil)
        store.focusNextPanel()
        XCTAssertEqual(store.focusedPanelID, firstPanelID)

        store.focus(panelID: nil)
        store.focusPreviousPanel()
        XCTAssertEqual(store.focusedPanelID, secondPanelID)
    }

    @MainActor
    func testPanelStoreFocusNextAndPreviousRecoverFromUnknownFocus() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let tree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .empty)
        )
        let store = PanelStore(rootNode: tree)

        store.focusedPanelID = UUID()
        store.focusNextPanel()
        XCTAssertEqual(store.focusedPanelID, firstPanelID)

        store.focusedPanelID = UUID()
        store.focusPreviousPanel()
        XCTAssertEqual(store.focusedPanelID, secondPanelID)
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
            ratio: 0.37,
            first: .leaf(id: firstPanelID, surface: .terminal(sessionID: terminalID)),
            second: .leaf(id: secondPanelID, surface: .editor(documentID: documentID))
        )
        let snapshot = WorkspaceSnapshot(workspace: workspace, panelTree: panelTree)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, WorkspaceSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.workspaceID, workspaceID)
        XCTAssertEqual(decoded.panelTree, panelTree)
        XCTAssertEqual(decoded.panelTree?.ratio, 0.37)
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

    func testFileBackedWorkspaceRepositoryRoundTripsSnapshot() async throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SmuxRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let rootURL = baseURL.appendingPathComponent("Root Workspace", isDirectory: true)
        let otherRootURL = baseURL.appendingPathComponent("Other Workspace", isDirectory: true)
        let repository = FileBackedWorkspaceRepository(baseDirectory: baseURL)
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: rootURL,
            openedAt: Date(timeIntervalSince1970: 100)
        )
        let panelTree = PanelNode.leaf(
            id: UUID(),
            surface: .terminal(sessionID: TerminalSession.ID())
        )
        let snapshot = WorkspaceSnapshot(workspace: workspace, panelTree: panelTree)

        defer {
            try? FileManager.default.removeItem(at: baseURL)
        }

        try await repository.saveSnapshot(snapshot, for: rootURL)

        let loadedSnapshot = try await repository.loadSnapshot(for: rootURL)
        let missingSnapshot = try await repository.loadSnapshot(for: otherRootURL)

        XCTAssertEqual(loadedSnapshot, snapshot)
        XCTAssertNil(missingSnapshot)
    }

    func testFileBackedWorkspaceRepositoryUsesCanonicalRootNameForSnapshotFile() async throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SmuxRepositoryCanonicalTests-\(UUID().uuidString)", isDirectory: true)
        let snapshotDirectoryURL = baseURL.appendingPathComponent("Snapshots", isDirectory: true)
        let realRootURL = baseURL.appendingPathComponent("Real Workspace", isDirectory: true)
        let linkedRootURL = baseURL.appendingPathComponent("Linked Workspace", isDirectory: true)
        let repository = FileBackedWorkspaceRepository(baseDirectory: snapshotDirectoryURL)
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: linkedRootURL,
            openedAt: Date(timeIntervalSince1970: 100)
        )
        let snapshot = WorkspaceSnapshot(workspace: workspace, panelTree: .placeholder)

        defer {
            try? FileManager.default.removeItem(at: baseURL)
        }

        try FileManager.default.createDirectory(
            at: realRootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createSymbolicLink(at: linkedRootURL, withDestinationURL: realRootURL)

        try await repository.saveSnapshot(snapshot, for: linkedRootURL)

        let snapshotFileNames = try FileManager.default.contentsOfDirectory(atPath: snapshotDirectoryURL.path)
        XCTAssertEqual(snapshotFileNames.count, 1)
        XCTAssertTrue(snapshotFileNames.first?.hasPrefix("Real-Workspace-") == true)
    }

    @MainActor
    func testRecentWorkspaceStoreUpsertsAndRemovesEntries() {
        let first = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/RecentOne"),
            openedAt: Date(timeIntervalSince1970: 1)
        )
        let second = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/RecentTwo"),
            openedAt: Date(timeIntervalSince1970: 2)
        )
        let sameRootAsFirst = Workspace.make(
            id: UUID(),
            rootURL: first.rootURL,
            displayName: "RecentOneAgain",
            openedAt: Date(timeIntervalSince1970: 3)
        )
        let store = RecentWorkspaceStore(repository: NoopRecentWorkspaceRepository())

        store.noteOpened(first)
        store.noteOpened(second)
        store.noteOpened(sameRootAsFirst)

        XCTAssertEqual(store.recentWorkspaces.map(\.id), [sameRootAsFirst.id, second.id])
        XCTAssertEqual(store.recentWorkspaces.first?.displayName, "RecentOneAgain")

        store.remove(id: second.id)

        XCTAssertEqual(store.recentWorkspaces.map(\.id), [sameRootAsFirst.id])
    }

    @MainActor
    func testRecentWorkspaceStorePersistsRoundTrip() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SmuxRecentWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = baseURL.appendingPathComponent("RecentWorkspaces.json", isDirectory: false)
        let repository = FileBackedRecentWorkspaceRepository(fileURL: fileURL)
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: baseURL.appendingPathComponent("Persisted Workspace", isDirectory: true),
            openedAt: Date(timeIntervalSince1970: 42)
        )

        defer {
            try? FileManager.default.removeItem(at: baseURL)
        }

        let store = RecentWorkspaceStore(repository: repository)
        store.noteOpened(workspace)

        let reloadedStore = RecentWorkspaceStore(repository: repository)

        XCTAssertEqual(reloadedStore.recentWorkspaces, store.recentWorkspaces)
        XCTAssertEqual(reloadedStore.recentWorkspaces.first?.id, workspace.id)
        XCTAssertEqual(reloadedStore.recentWorkspaces.first?.displayName, workspace.displayName)
    }

    @MainActor
    func testWorkspaceCoordinatorOpenRestoresPanelTreeAndUpdatesRecent() async throws {
        let activeRootURL = URL(fileURLWithPath: "/tmp/ActiveWorkspace")
        let restoredRootURL = URL(fileURLWithPath: "/tmp/RestoredWorkspace")
        let activeWorkspace = Workspace.make(
            id: UUID(),
            rootURL: activeRootURL,
            openedAt: Date(timeIntervalSince1970: 10)
        )
        let restoredWorkspace = Workspace.make(
            id: UUID(),
            rootURL: restoredRootURL,
            openedAt: Date(timeIntervalSince1970: 20)
        )
        let activePanelTree = PanelNode.leaf(
            id: UUID(),
            surface: .terminal(sessionID: TerminalSession.ID())
        )
        let firstPanelID = PanelNode.ID()
        let secondPanelID = PanelNode.ID()
        let previewID = PreviewState.ID()
        let documentID = DocumentSession.ID()
        let restoredDocument = DocumentSession.make(
            id: documentID,
            workspaceID: restoredWorkspace.id,
            url: restoredRootURL.appendingPathComponent("README.md")
        )
        let restoredPreview = PreviewState(
            id: previewID,
            sourceDocumentID: documentID,
            renderVersion: 3,
            sanitizedMarkdown: SanitizedMarkdown(html: "<h1>Restored</h1>"),
            mermaidBlocks: [],
            errors: [],
            zoom: 1,
            scrollAnchor: nil
        )
        let restoredPanelTree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .preview(previewID: previewID))
        )
        let restoredSnapshot = WorkspaceSnapshot(
            workspace: restoredWorkspace,
            panelTree: restoredPanelTree,
            documents: [restoredDocument],
            previews: [restoredPreview],
            leftRailState: LeftRailState(
                selectedWorkspaceID: restoredWorkspace.id,
                selectedPanelID: secondPanelID,
                isFileTreeVisible: true
            )
        )
        let repository = InMemoryWorkspaceRepository()
        let workspaceStore = WorkspaceStore(activeWorkspace: activeWorkspace)
        let panelStore = PanelStore(rootNode: activePanelTree)
        let documentSessionStore = DocumentSessionStore()
        let previewSessionStore = PreviewSessionStore()
        let recentStore = RecentWorkspaceStore(repository: NoopRecentWorkspaceRepository())
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: repository,
            recentWorkspaceStore: recentStore,
            gitBranchProvider: NoopGitBranchProvider(),
            documentSessionStore: documentSessionStore,
            previewSessionStore: previewSessionStore
        )
        await repository.setSnapshot(restoredSnapshot, for: restoredRootURL)

        try await coordinator.openWorkspace(rootURL: restoredRootURL)

        let savedActiveSnapshot = await repository.savedSnapshot(for: activeRootURL)
        XCTAssertEqual(savedActiveSnapshot?.workspaceID, activeWorkspace.id)
        XCTAssertEqual(savedActiveSnapshot?.panelTree, activePanelTree)
        XCTAssertEqual(workspaceStore.activeWorkspace?.id, restoredWorkspace.id)
        XCTAssertEqual(panelStore.rootNode, restoredPanelTree)
        XCTAssertEqual(panelStore.focusedPanelID, secondPanelID)
        XCTAssertEqual(documentSessionStore.session(for: documentID), restoredDocument)
        XCTAssertEqual(previewSessionStore.state(for: previewID), restoredPreview)
        XCTAssertEqual(previewSessionStore.sourceDocumentID(for: previewID), documentID)
        XCTAssertEqual(recentStore.recentWorkspaces.map(\.id), [restoredWorkspace.id])
        XCTAssertFalse(workspaceStore.isOpeningWorkspace)
        XCTAssertNil(workspaceStore.openErrorMessage)
    }

    @MainActor
    func testWorkspaceCoordinatorOpenSetsDetectedGitBranch() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/GitBranchWorkspace")
        let workspaceStore = WorkspaceStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: PanelStore(),
            workspaceRepository: NoopWorkspaceRepository(),
            gitBranchProvider: FixedGitBranchProvider(result: .branch("feature/workspaces"))
        )

        try await coordinator.openWorkspace(rootURL: rootURL)

        XCTAssertEqual(workspaceStore.activeWorkspace?.rootURL, rootURL)
        XCTAssertEqual(workspaceStore.activeWorkspace?.gitBranch, "feature/workspaces")
    }

    @MainActor
    func testWorkspaceCoordinatorOpenStopsDocumentWatchersAndClearsTextSnapshots() async throws {
        let activeWorkspace = Workspace.make(rootURL: URL(fileURLWithPath: "/tmp/ActiveWorkspace"))
        let nextRootURL = URL(fileURLWithPath: "/tmp/NextWorkspace")
        let documentURL = activeWorkspace.rootURL.appendingPathComponent("Draft.md")
        let documentID = DocumentSession.ID()
        let watcher = ManualFileWatcher()
        let documentFileWatchStore = DocumentFileWatchStore(fileWatcher: watcher)
        let documentTextStore = DocumentTextStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: WorkspaceStore(activeWorkspace: activeWorkspace),
            panelStore: PanelStore(),
            workspaceRepository: NoopWorkspaceRepository(),
            gitBranchProvider: NoopGitBranchProvider(),
            documentFileWatchStore: documentFileWatchStore,
            documentTextStore: documentTextStore
        )

        try documentFileWatchStore.startWatching(documentID: documentID, url: documentURL)
        documentTextStore.update(documentID: documentID, text: "Draft", version: 1)

        try await coordinator.openWorkspace(rootURL: nextRootURL)
        watcher.emit(FileWatchEvent(scope: .openFile(documentURL), kind: .modified))
        await Task.yield()

        XCTAssertNil(documentFileWatchStore.latestEvent(for: documentID))
        XCTAssertNil(documentTextStore.snapshot(for: documentID))
    }

    @MainActor
    func testWorkspaceCoordinatorRejectsReentrantOpenAndDoesNotCommitSecondWorkspace() async throws {
        let firstRootURL = URL(fileURLWithPath: "/tmp/ReentrantFirst")
        let secondRootURL = URL(fileURLWithPath: "/tmp/ReentrantSecond")
        let repository = SlowWorkspaceRepository()
        let workspaceStore = WorkspaceStore()
        let panelStore = PanelStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: repository,
            gitBranchProvider: NoopGitBranchProvider()
        )

        let firstOpenTask = Task { @MainActor in
            try await coordinator.openWorkspace(rootURL: firstRootURL)
        }
        await repository.waitUntilLoadStarted()

        do {
            try await coordinator.openWorkspace(rootURL: secondRootURL)
            XCTFail("Expected reentrant open to throw.")
        } catch let error as WorkspaceCoordinatorError {
            XCTAssertEqual(error, .workspaceOpenInProgress)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await repository.finishLoad()
        try await firstOpenTask.value

        XCTAssertEqual(workspaceStore.activeWorkspace?.rootURL, firstRootURL)
        XCTAssertFalse(workspaceStore.workspaces.contains { $0.rootURL == secondRootURL })
        XCTAssertFalse(workspaceStore.isOpeningWorkspace)
    }

    @MainActor
    func testWorkspaceCoordinatorOpenFallsBackWhenSnapshotLoadThrows() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/RestoreFallback")
        let repository = ThrowingLoadWorkspaceRepository()
        let workspaceStore = WorkspaceStore()
        let panelStore = PanelStore(
            rootNode: .leaf(surface: .terminal(sessionID: TerminalSession.ID()))
        )
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: repository,
            gitBranchProvider: NoopGitBranchProvider()
        )

        try await coordinator.openWorkspace(rootURL: rootURL)

        XCTAssertEqual(workspaceStore.activeWorkspace?.rootURL, rootURL)
        XCTAssertEqual(panelStore.rootNode.surface, .empty)
        XCTAssertEqual(panelStore.focusedPanelID, panelStore.rootNode.id)
        XCTAssertTrue(workspaceStore.openErrorMessage?.contains("Failed to restore workspace state") == true)
        XCTAssertFalse(workspaceStore.isOpeningWorkspace)
    }

    @MainActor
    func testWorkspaceCoordinatorOpenDocumentCreatesSessionAndBindsSplitPreviewToSameDocument() async throws {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/DocumentWorkspace")
        )
        let documentURL = workspace.rootURL.appendingPathComponent("README.md")
        let workspaceStore = WorkspaceStore(activeWorkspace: workspace)
        let panelStore = PanelStore(rootNode: .leaf(surface: .empty))
        let documentSessionStore = DocumentSessionStore()
        let previewSessionStore = PreviewSessionStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            documentSessionStore: documentSessionStore,
            previewSessionStore: previewSessionStore
        )

        try await coordinator.openDocument(documentURL, preferredSurface: .split)

        guard case let .editor(documentID) = panelStore.rootNode.children.first?.surface,
              case let .preview(previewID) = panelStore.rootNode.children.last?.surface
        else {
            XCTFail("Expected split editor and preview surfaces.")
            return
        }

        let session = documentSessionStore.session(for: documentID)
        XCTAssertEqual(session?.workspaceID, workspace.id)
        XCTAssertEqual(session?.url, documentURL)
        XCTAssertEqual(session?.language, .markdown)
        XCTAssertEqual(previewSessionStore.sourceDocumentID(for: previewID), documentID)
    }

    @MainActor
    func testWorkspaceCoordinatorOpenDocumentInNewEditorPanelSplitsFocusedPanel() async throws {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/NewEditorPanelWorkspace")
        )
        let documentURL = workspace.rootURL.appendingPathComponent("README.md")
        let existingPanelID = PanelNode.ID()
        let workspaceStore = WorkspaceStore(activeWorkspace: workspace)
        let panelStore = PanelStore(rootNode: .leaf(id: existingPanelID, surface: .empty))
        let documentSessionStore = DocumentSessionStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            documentSessionStore: documentSessionStore
        )

        try await coordinator.openDocumentInNewPanel(
            documentURL,
            preferredSurface: .editor,
            splitDirection: .horizontal
        )

        XCTAssertEqual(panelStore.rootNode.direction, .horizontal)
        XCTAssertEqual(panelStore.rootNode.children.first?.id, existingPanelID)

        guard case let .editor(documentID) = panelStore.rootNode.children.last?.surface else {
            XCTFail("Expected a new editor panel.")
            return
        }

        XCTAssertEqual(panelStore.focusedPanelID, panelStore.rootNode.children.last?.id)
        let session = documentSessionStore.session(for: documentID)
        XCTAssertEqual(session?.workspaceID, workspace.id)
        XCTAssertEqual(session?.url, documentURL)
    }

    @MainActor
    func testWorkspaceCoordinatorOpenDocumentInNewPreviewPanelBindsPreviewToDocument() async throws {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/NewPreviewPanelWorkspace")
        )
        let documentURL = workspace.rootURL.appendingPathComponent("diagram.mmd")
        let workspaceStore = WorkspaceStore(activeWorkspace: workspace)
        let panelStore = PanelStore(rootNode: .leaf(surface: .empty))
        let documentSessionStore = DocumentSessionStore()
        let previewSessionStore = PreviewSessionStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            documentSessionStore: documentSessionStore,
            previewSessionStore: previewSessionStore
        )

        try await coordinator.openDocumentInNewPanel(
            documentURL,
            preferredSurface: .preview,
            splitDirection: .horizontal
        )

        guard case let .preview(previewID) = panelStore.rootNode.children.last?.surface,
              let documentID = previewSessionStore.sourceDocumentID(for: previewID)
        else {
            XCTFail("Expected a new preview panel bound to a document.")
            return
        }

        XCTAssertEqual(panelStore.focusedPanelID, panelStore.rootNode.children.last?.id)
        XCTAssertEqual(documentSessionStore.session(for: documentID)?.url, documentURL)
    }

    @MainActor
    func testPreviewSessionStorePreservesZoomAcrossRenderUpdates() {
        let store = PreviewSessionStore()
        let previewID = PreviewState.ID()
        let documentID = DocumentSession.ID()
        let firstState = PreviewState(
            id: previewID,
            sourceDocumentID: documentID,
            renderVersion: 1,
            sanitizedMarkdown: SanitizedMarkdown(html: "<p>First</p>"),
            mermaidBlocks: [],
            errors: [],
            zoom: 1.6,
            scrollAnchor: nil
        )
        let nextRenderState = PreviewState(
            id: PreviewState.ID(),
            sourceDocumentID: documentID,
            renderVersion: 2,
            sanitizedMarkdown: SanitizedMarkdown(html: "<p>Second</p>"),
            mermaidBlocks: [],
            errors: [],
            zoom: PreviewState.defaultZoom,
            scrollAnchor: nil
        )

        store.upsertState(firstState, for: previewID)
        store.upsertState(nextRenderState, for: previewID)

        XCTAssertEqual(store.state(for: previewID)?.id, previewID)
        XCTAssertEqual(store.state(for: previewID)?.renderVersion, 2)
        XCTAssertEqual(store.state(for: previewID)?.sanitizedMarkdown, SanitizedMarkdown(html: "<p>Second</p>"))
        XCTAssertEqual(store.state(for: previewID)?.zoom, 1.6)
    }

    @MainActor
    func testPreviewSessionStoreClampsZoomUpdatesAndSnapshotsBoundPreview() {
        let store = PreviewSessionStore()
        let previewID = PreviewState.ID()
        let documentID = DocumentSession.ID()

        store.bind(previewID: previewID, sourceDocumentID: documentID)
        store.updateZoom(for: previewID, to: 12)

        let state = store.state(for: previewID)
        XCTAssertEqual(state?.sourceDocumentID, documentID)
        XCTAssertEqual(state?.zoom, PreviewState.maximumZoom)
        XCTAssertEqual(store.snapshotStates(), state.map { [$0] } ?? [])

        store.updateZoom(for: previewID, to: 0.1)

        XCTAssertEqual(store.state(for: previewID)?.zoom, PreviewState.minimumZoom)
    }

    @MainActor
    func testWorkspaceCoordinatorCreateTerminalStartsControllerSessionAndUsesReturnedID() async throws {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/TerminalWorkspace")
        )
        let workspaceStore = WorkspaceStore(activeWorkspace: workspace)
        let panelStore = PanelStore(rootNode: .leaf(surface: .empty))
        let client = WorkspacePanelMockPTYClient(processID: 2468)
        let terminalSessionController = TerminalSessionController(
            ptyFactory: WorkspacePanelMockPTYClientFactory(client: client)
        )
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            terminalSessionController: terminalSessionController
        )

        try await coordinator.createTerminal(in: workspace.id)

        guard case let .terminal(sessionID) = panelStore.rootNode.surface else {
            XCTFail("Expected terminal surface.")
            return
        }

        let session = terminalSessionController.session(for: sessionID)
        XCTAssertEqual(session?.workspaceID, workspace.id)
        XCTAssertEqual(session?.workingDirectory, workspace.rootURL)
        XCTAssertEqual(session?.processID, 2468)
        XCTAssertEqual(session?.status, .running)
        XCTAssertEqual(client.startRequests.count, 1)
        XCTAssertEqual(client.startRequests.first?.workingDirectory, workspace.rootURL)
    }

    @MainActor
    func testWorkspaceCoordinatorCreateTerminalReplacesRequestedPanel() async throws {
        let workspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/TargetedTerminalWorkspace")
        )
        let firstPanelID = PanelNode.ID()
        let secondPanelID = PanelNode.ID()
        let panelStore = PanelStore(
            rootNode: .split(
                direction: .horizontal,
                first: .leaf(id: firstPanelID, surface: .empty),
                second: .leaf(id: secondPanelID, surface: .empty)
            ),
            focusedPanelID: firstPanelID
        )
        let client = WorkspacePanelMockPTYClient(processID: 1357)
        let terminalSessionController = TerminalSessionController(
            ptyFactory: WorkspacePanelMockPTYClientFactory(client: client)
        )
        let coordinator = WorkspaceCoordinator(
            workspaceStore: WorkspaceStore(activeWorkspace: workspace),
            panelStore: panelStore,
            terminalSessionController: terminalSessionController
        )

        try await coordinator.createTerminal(in: workspace.id, replacingPanel: secondPanelID)

        XCTAssertEqual(panelStore.rootNode.children.first?.surface, .empty)
        guard case let .terminal(sessionID) = panelStore.rootNode.children.last?.surface else {
            XCTFail("Expected terminal surface in requested panel.")
            return
        }
        XCTAssertEqual(panelStore.focusedPanelID, secondPanelID)
        XCTAssertEqual(terminalSessionController.session(for: sessionID)?.processID, 1357)
    }

    @MainActor
    func testWorkspaceCoordinatorCloseSavesSnapshotAndRemovesWorkspace() async throws {
        let activeWorkspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/CloseActive"),
            openedAt: Date(timeIntervalSince1970: 10)
        )
        let remainingWorkspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/CloseRemaining"),
            openedAt: Date(timeIntervalSince1970: 20)
        )
        let panelTree = PanelNode.leaf(
            id: UUID(),
            surface: .editor(documentID: DocumentSession.ID())
        )
        let repository = InMemoryWorkspaceRepository()
        let workspaceStore = WorkspaceStore(
            activeWorkspace: activeWorkspace,
            workspaces: [activeWorkspace, remainingWorkspace]
        )
        let panelStore = PanelStore(rootNode: panelTree)
        let documentSessionStore = DocumentSessionStore()
        let watcher = ManualFileWatcher()
        let documentFileWatchStore = DocumentFileWatchStore(fileWatcher: watcher)
        let documentTextStore = DocumentTextStore()
        let previewSessionStore = PreviewSessionStore()
        let terminalSessionController = TerminalSessionController(
            ptyFactory: WorkspacePanelMockPTYClientFactory(client: WorkspacePanelMockPTYClient(processID: 1111))
        )
        let documentSession = DocumentSession.make(
            workspaceID: activeWorkspace.id,
            url: activeWorkspace.rootURL.appendingPathComponent("Draft.md")
        )
        let previewState = PreviewState(
            id: PreviewState.ID(),
            sourceDocumentID: documentSession.id,
            renderVersion: 2,
            sanitizedMarkdown: SanitizedMarkdown(html: "<p>Draft</p>"),
            mermaidBlocks: [],
            errors: [],
            zoom: 1,
            scrollAnchor: nil
        )
        let recentStore = RecentWorkspaceStore(repository: NoopRecentWorkspaceRepository())
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: repository,
            recentWorkspaceStore: recentStore,
            documentSessionStore: documentSessionStore,
            documentFileWatchStore: documentFileWatchStore,
            documentTextStore: documentTextStore,
            terminalSessionController: terminalSessionController,
            previewSessionStore: previewSessionStore
        )
        documentSessionStore.upsertSession(documentSession)
        try documentFileWatchStore.startWatching(documentID: documentSession.id, url: documentSession.url)
        documentTextStore.update(documentID: documentSession.id, text: "Draft", version: 1)
        previewSessionStore.upsertState(previewState, for: previewState.id)
        recentStore.noteOpened(activeWorkspace)

        await coordinator.closeWorkspace(id: activeWorkspace.id)
        watcher.emit(FileWatchEvent(scope: .openFile(documentSession.url), kind: .modified))
        await Task.yield()

        let savedSnapshot = await repository.savedSnapshot(for: activeWorkspace.rootURL)
        XCTAssertEqual(savedSnapshot?.workspaceID, activeWorkspace.id)
        XCTAssertEqual(savedSnapshot?.panelTree, panelTree)
        XCTAssertEqual(savedSnapshot?.documents, [documentSession])
        XCTAssertEqual(savedSnapshot?.previews, [previewState])
        XCTAssertNil(documentFileWatchStore.latestEvent(for: documentSession.id))
        XCTAssertNil(documentTextStore.snapshot(for: documentSession.id))
        XCTAssertEqual(workspaceStore.workspaces.map(\.id), [remainingWorkspace.id])
        XCTAssertEqual(workspaceStore.activeWorkspace?.id, remainingWorkspace.id)
        XCTAssertEqual(recentStore.recentWorkspaces.map(\.id), [activeWorkspace.id])
    }

    @MainActor
    func testWorkspaceCoordinatorCloseKeepsActiveWorkspaceWhenSnapshotSaveFails() async {
        let activeWorkspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/CloseSaveFailsActive"),
            openedAt: Date(timeIntervalSince1970: 10)
        )
        let remainingWorkspace = Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: "/tmp/CloseSaveFailsRemaining"),
            openedAt: Date(timeIntervalSince1970: 20)
        )
        let workspaceStore = WorkspaceStore(
            activeWorkspace: activeWorkspace,
            workspaces: [activeWorkspace, remainingWorkspace]
        )
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: PanelStore(),
            workspaceRepository: ThrowingSaveWorkspaceRepository()
        )

        await coordinator.closeWorkspace(id: activeWorkspace.id)

        XCTAssertEqual(workspaceStore.activeWorkspace?.id, activeWorkspace.id)
        XCTAssertEqual(workspaceStore.workspaces.map(\.id), [activeWorkspace.id, remainingWorkspace.id])
        XCTAssertTrue(workspaceStore.openErrorMessage?.contains("Failed to close workspace") == true)
    }

    @MainActor
    func testWorkspaceCoordinatorFocusCommandsForwardToPanelStore() {
        let firstPanelID = UUID()
        let secondPanelID = UUID()
        let panelStore = PanelStore(
            rootNode: .split(
                direction: .horizontal,
                first: .leaf(id: firstPanelID, surface: .empty),
                second: .leaf(id: secondPanelID, surface: .empty)
            ),
            focusedPanelID: firstPanelID
        )
        let coordinator = WorkspaceCoordinator(panelStore: panelStore)

        coordinator.focusNextPanel()
        XCTAssertEqual(panelStore.focusedPanelID, secondPanelID)

        coordinator.focusPreviousPanel()
        XCTAssertEqual(panelStore.focusedPanelID, firstPanelID)
    }

    @MainActor
    func testAppCommandRouterForwardsCommands() async throws {
        let handler = RecordingCommandHandler()
        let router = AppCommandRouter(
            workspaceOpening: handler,
            documentOpening: handler,
            terminalCommanding: handler,
            panelCommanding: handler
        )
        let rootURL = URL(fileURLWithPath: "/tmp/RoutedWorkspace")
        let documentURL = URL(fileURLWithPath: "/tmp/RoutedWorkspace/README.md")
        let workspaceID = Workspace.ID()
        let closedWorkspaceID = Workspace.ID()
        let panelID = PanelNode.ID()
        let splitSurface = PanelSurfaceDescriptor.empty

        try await router.openWorkspace(rootURL: rootURL)
        try await router.closeWorkspace(id: closedWorkspaceID)
        try await router.openDocument(documentURL, preferredSurface: .split)
        try await router.openDocumentInNewPanel(
            documentURL,
            preferredSurface: .preview,
            splitDirection: .horizontal
        )
        try await router.createTerminal(in: workspaceID)
        try await router.createTerminal(in: workspaceID, replacingPanel: panelID)
        router.splitFocusedPanel(direction: .vertical, surface: splitSurface)
        router.focusNextPanel()
        router.focusPreviousPanel()

        XCTAssertEqual(handler.openedRootURL, rootURL)
        XCTAssertEqual(handler.closedWorkspaceID, closedWorkspaceID)
        XCTAssertEqual(handler.openedDocumentURL, documentURL)
        XCTAssertEqual(handler.openedDocumentModes, [.split, .preview])
        XCTAssertEqual(handler.openedDocumentSplitDirection, .horizontal)
        XCTAssertEqual(handler.terminalWorkspaceID, workspaceID)
        XCTAssertEqual(handler.terminalPanelID, panelID)
        XCTAssertEqual(handler.splitDirection, .vertical)
        XCTAssertEqual(handler.splitSurface, splitSurface)
        XCTAssertEqual(handler.focusNextCount, 1)
        XCTAssertEqual(handler.focusPreviousCount, 1)
    }

    @MainActor
    func testAppCommandRouterThrowsForMissingAsyncHandlersAndNoOpsSyncPanelCommands() async {
        let router = AppCommandRouter()
        let rootURL = URL(fileURLWithPath: "/tmp/MissingWorkspace")
        let documentURL = URL(fileURLWithPath: "/tmp/MissingWorkspace/README.md")

        do {
            try await router.openWorkspace(rootURL: rootURL)
            XCTFail("Expected missing workspace handler error.")
        } catch let error as AppCommandRouterError {
            XCTAssertEqual(error, .missingWorkspaceOpening)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await router.closeWorkspace(id: Workspace.ID())
            XCTFail("Expected missing workspace handler error.")
        } catch let error as AppCommandRouterError {
            XCTAssertEqual(error, .missingWorkspaceOpening)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await router.openDocument(documentURL, preferredSurface: .editor)
            XCTFail("Expected missing document handler error.")
        } catch let error as AppCommandRouterError {
            XCTAssertEqual(error, .missingDocumentOpening)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await router.openDocumentInNewPanel(
                documentURL,
                preferredSurface: .preview,
                splitDirection: .horizontal
            )
            XCTFail("Expected missing document handler error.")
        } catch let error as AppCommandRouterError {
            XCTAssertEqual(error, .missingDocumentOpening)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await router.createTerminal(in: Workspace.ID())
            XCTFail("Expected missing terminal handler error.")
        } catch let error as AppCommandRouterError {
            XCTAssertEqual(error, .missingTerminalCommanding)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        router.splitFocusedPanel(direction: .horizontal, surface: .empty)
        router.focusNextPanel()
        router.focusPreviousPanel()
    }

    private actor InMemoryWorkspaceRepository: WorkspaceRepository {
        private var snapshotsByPath: [String: WorkspaceSnapshot] = [:]
        private var savedSnapshotsByPath: [String: WorkspaceSnapshot] = [:]

        func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
            snapshotsByPath[key(for: rootURL)]
        }

        func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws {
            savedSnapshotsByPath[key(for: rootURL)] = snapshot
        }

        func setSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) {
            snapshotsByPath[key(for: rootURL)] = snapshot
        }

        func savedSnapshot(for rootURL: URL) -> WorkspaceSnapshot? {
            savedSnapshotsByPath[key(for: rootURL)]
        }

        private func key(for rootURL: URL) -> String {
            rootURL.standardizedFileURL.path
        }
    }

    private struct FixedGitBranchProvider: GitBranchProviding {
        var result: GitBranchLookupResult

        func currentBranch(for rootURL: URL) async -> GitBranchLookupResult {
            result
        }
    }

    private actor SlowWorkspaceRepository: WorkspaceRepository {
        private var loadStartedContinuation: CheckedContinuation<Void, Never>?
        private var finishLoadContinuation: CheckedContinuation<WorkspaceSnapshot?, Never>?
        private var isLoadStarted = false

        func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
            isLoadStarted = true

            return await withCheckedContinuation { continuation in
                finishLoadContinuation = continuation
                loadStartedContinuation?.resume()
                loadStartedContinuation = nil
            }
        }

        func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws {}

        func waitUntilLoadStarted() async {
            guard !isLoadStarted else {
                return
            }

            await withCheckedContinuation { continuation in
                loadStartedContinuation = continuation
            }
        }

        func finishLoad(snapshot: WorkspaceSnapshot? = nil) {
            finishLoadContinuation?.resume(returning: snapshot)
            finishLoadContinuation = nil
        }
    }

    private struct ThrowingLoadWorkspaceRepository: WorkspaceRepository {
        func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
            throw WorkspaceRepositoryTestError.loadFailed
        }

        func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws {}
    }

    private struct ThrowingSaveWorkspaceRepository: WorkspaceRepository {
        func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
            nil
        }

        func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws {
            throw WorkspaceRepositoryTestError.saveFailed
        }
    }

    private enum WorkspaceRepositoryTestError: LocalizedError {
        case loadFailed
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed:
                return "Snapshot load failed."
            case .saveFailed:
                return "Snapshot save failed."
            }
        }
    }

    @MainActor
    private final class RecordingCommandHandler: WorkspaceOpening, DocumentOpening, TerminalCommanding, PanelCommanding {
        var openedRootURL: URL?
        var closedWorkspaceID: Workspace.ID?
        var openedDocumentURL: URL?
        var openedDocumentModes: [DocumentOpenMode] = []
        var openedDocumentSplitDirection: SplitDirection?
        var terminalWorkspaceID: Workspace.ID?
        var terminalPanelID: PanelNode.ID?
        var splitDirection: SplitDirection?
        var splitSurface: PanelSurfaceDescriptor?
        var focusNextCount = 0
        var focusPreviousCount = 0

        func openWorkspace(rootURL: URL) async throws {
            openedRootURL = rootURL
        }

        func closeWorkspace(id: Workspace.ID) async {
            closedWorkspaceID = id
        }

        func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {
            openedDocumentURL = url
            openedDocumentModes.append(preferredSurface)
        }

        func openDocumentInNewPanel(
            _ url: URL,
            preferredSurface: DocumentOpenMode,
            splitDirection: SplitDirection
        ) async throws {
            openedDocumentURL = url
            openedDocumentModes.append(preferredSurface)
            openedDocumentSplitDirection = splitDirection
        }

        func createTerminal(in workspaceID: Workspace.ID) async throws {
            terminalWorkspaceID = workspaceID
        }

        func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID?) async throws {
            terminalWorkspaceID = workspaceID
            terminalPanelID = panelID
        }

        func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID) async throws {
            terminalWorkspaceID = workspaceID
            terminalPanelID = panelID
        }

        func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
            splitDirection = direction
            splitSurface = surface
        }

        func focusNextPanel() {
            focusNextCount += 1
        }

        func focusPreviousPanel() {
            focusPreviousCount += 1
        }
    }
}

private final class WorkspacePanelMockPTYClient: PTYClient {
    var outputHandler: (@Sendable (Data) -> Void)?
    var terminationHandler: (@Sendable (Int32) -> Void)?
    private(set) var processID: Int32?
    private(set) var startRequests: [PTYLaunchRequest] = []
    private let launchProcessID: Int32

    init(processID: Int32) {
        self.launchProcessID = processID
    }

    func start(_ request: PTYLaunchRequest) throws -> PTYLaunchResult {
        startRequests.append(request)
        processID = launchProcessID
        return PTYLaunchResult(processID: launchProcessID)
    }

    func write(_ data: Data) throws {}

    func resize(columns: Int, rows: Int) throws {}

    func terminate() {}
}

private final class WorkspacePanelMockPTYClientFactory: PTYClientFactory, @unchecked Sendable {
    private let client: WorkspacePanelMockPTYClient

    init(client: WorkspacePanelMockPTYClient) {
        self.client = client
    }

    func makeClient() -> any PTYClient {
        client
    }
}
