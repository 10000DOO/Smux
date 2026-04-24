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
        let store = RecentWorkspaceStore()

        store.noteOpened(first)
        store.noteOpened(second)
        store.noteOpened(sameRootAsFirst)

        XCTAssertEqual(store.recentWorkspaces.map(\.id), [sameRootAsFirst.id, second.id])
        XCTAssertEqual(store.recentWorkspaces.first?.displayName, "RecentOneAgain")

        store.remove(id: second.id)

        XCTAssertEqual(store.recentWorkspaces.map(\.id), [sameRootAsFirst.id])
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
        let restoredPanelTree = PanelNode.split(
            direction: .horizontal,
            first: .leaf(id: firstPanelID, surface: .empty),
            second: .leaf(id: secondPanelID, surface: .preview(previewID: PreviewState.ID()))
        )
        let restoredSnapshot = WorkspaceSnapshot(
            workspace: restoredWorkspace,
            panelTree: restoredPanelTree,
            leftRailState: LeftRailState(
                selectedWorkspaceID: restoredWorkspace.id,
                selectedPanelID: secondPanelID,
                isFileTreeVisible: true
            )
        )
        let repository = InMemoryWorkspaceRepository()
        let workspaceStore = WorkspaceStore(activeWorkspace: activeWorkspace)
        let panelStore = PanelStore(rootNode: activePanelTree)
        let recentStore = RecentWorkspaceStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: repository,
            recentWorkspaceStore: recentStore
        )
        await repository.setSnapshot(restoredSnapshot, for: restoredRootURL)

        try await coordinator.openWorkspace(rootURL: restoredRootURL)

        let savedActiveSnapshot = await repository.savedSnapshot(for: activeRootURL)
        XCTAssertEqual(savedActiveSnapshot?.workspaceID, activeWorkspace.id)
        XCTAssertEqual(savedActiveSnapshot?.panelTree, activePanelTree)
        XCTAssertEqual(workspaceStore.activeWorkspace?.id, restoredWorkspace.id)
        XCTAssertEqual(panelStore.rootNode, restoredPanelTree)
        XCTAssertEqual(panelStore.focusedPanelID, secondPanelID)
        XCTAssertEqual(recentStore.recentWorkspaces.map(\.id), [restoredWorkspace.id])
        XCTAssertFalse(workspaceStore.isOpeningWorkspace)
        XCTAssertNil(workspaceStore.openErrorMessage)
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
            workspaceRepository: repository
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
            workspaceRepository: repository
        )

        try await coordinator.openWorkspace(rootURL: rootURL)

        XCTAssertEqual(workspaceStore.activeWorkspace?.rootURL, rootURL)
        XCTAssertEqual(panelStore.rootNode.surface, .empty)
        XCTAssertEqual(panelStore.focusedPanelID, panelStore.rootNode.id)
        XCTAssertTrue(workspaceStore.openErrorMessage?.contains("Failed to restore workspace state") == true)
        XCTAssertFalse(workspaceStore.isOpeningWorkspace)
    }

    @MainActor
    func testWorkspaceCoordinatorCloseSavesSnapshotAndRemovesWorkspace() async {
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
        let recentStore = RecentWorkspaceStore()
        let coordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: repository,
            recentWorkspaceStore: recentStore
        )
        recentStore.noteOpened(activeWorkspace)

        await coordinator.closeWorkspace(id: activeWorkspace.id)

        let savedSnapshot = await repository.savedSnapshot(for: activeWorkspace.rootURL)
        XCTAssertEqual(savedSnapshot?.workspaceID, activeWorkspace.id)
        XCTAssertEqual(savedSnapshot?.panelTree, panelTree)
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
        let splitSurface = PanelSurfaceDescriptor.empty

        try await router.openWorkspace(rootURL: rootURL)
        try await router.openDocument(documentURL, preferredSurface: .split)
        try await router.createTerminal(in: workspaceID)
        router.splitFocusedPanel(direction: .vertical, surface: splitSurface)

        XCTAssertEqual(handler.openedRootURL, rootURL)
        XCTAssertEqual(handler.openedDocumentURL, documentURL)
        XCTAssertEqual(handler.openedDocumentMode, .split)
        XCTAssertEqual(handler.terminalWorkspaceID, workspaceID)
        XCTAssertEqual(handler.splitDirection, .vertical)
        XCTAssertEqual(handler.splitSurface, splitSurface)
    }

    @MainActor
    func testAppCommandRouterThrowsForMissingAsyncHandlersAndNoOpsSyncSplit() async {
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
            try await router.openDocument(documentURL, preferredSurface: .editor)
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
        var openedDocumentMode: DocumentOpenMode?
        var terminalWorkspaceID: Workspace.ID?
        var splitDirection: SplitDirection?
        var splitSurface: PanelSurfaceDescriptor?

        func openWorkspace(rootURL: URL) async throws {
            openedRootURL = rootURL
        }

        func closeWorkspace(id: Workspace.ID) async {
            closedWorkspaceID = id
        }

        func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {
            openedDocumentURL = url
            openedDocumentMode = preferredSurface
        }

        func createTerminal(in workspaceID: Workspace.ID) async throws {
            terminalWorkspaceID = workspaceID
        }

        func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
            splitDirection = direction
            splitSurface = surface
        }
    }
}
