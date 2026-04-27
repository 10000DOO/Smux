import Foundation

@MainActor
final class WorkspaceCoordinator: WorkspaceOpening, DocumentOpening, TerminalCommanding, WorkspaceSessionCreating, WorkspaceSessionCommanding, WorkspaceLayoutSessionCommanding, PanelCommanding {
    var workspaceStore: WorkspaceStore?
    var panelStore: PanelStore?
    var workspaceRepository: (any WorkspaceRepository)?
    var recentWorkspaceStore: RecentWorkspaceStore?
    var gitBranchProvider: any GitBranchProviding
    var documentSessionStore: DocumentSessionStore?
    var documentFileWatchStore: DocumentFileWatchStore?
    var documentTextStore: DocumentTextStore?
    var terminalSessionController: TerminalSessionController?
    var previewSessionStore: PreviewSessionStore?
    var previewRenderCoordinator: (any PreviewRenderingCoordinating)?
    var workspaceSessionStore: WorkspaceSessionStore?
    var workspaceLayoutSessionStore: WorkspaceLayoutSessionStore?
    var workspaceRuntimeStore: WorkspaceRuntimeStore?

    private var workspaceIDsPendingSnapshotRetry: Set<Workspace.ID> = []

    init(
        workspaceStore: WorkspaceStore? = nil,
        panelStore: PanelStore? = nil,
        workspaceRepository: (any WorkspaceRepository)? = nil,
        recentWorkspaceStore: RecentWorkspaceStore? = nil,
        gitBranchProvider: any GitBranchProviding = ProcessGitBranchProvider(),
        documentSessionStore: DocumentSessionStore? = nil,
        documentFileWatchStore: DocumentFileWatchStore? = nil,
        documentTextStore: DocumentTextStore? = nil,
        terminalSessionController: TerminalSessionController? = nil,
        previewSessionStore: PreviewSessionStore? = nil,
        previewRenderCoordinator: (any PreviewRenderingCoordinating)? = nil,
        workspaceSessionStore: WorkspaceSessionStore? = nil,
        workspaceLayoutSessionStore: WorkspaceLayoutSessionStore? = nil,
        workspaceRuntimeStore: WorkspaceRuntimeStore? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.workspaceRepository = workspaceRepository
        self.recentWorkspaceStore = recentWorkspaceStore
        self.gitBranchProvider = gitBranchProvider
        self.documentSessionStore = documentSessionStore
        self.documentFileWatchStore = documentFileWatchStore
        self.documentTextStore = documentTextStore
        self.terminalSessionController = terminalSessionController
        self.previewSessionStore = previewSessionStore
        self.previewRenderCoordinator = previewRenderCoordinator
        self.workspaceSessionStore = workspaceSessionStore
        self.workspaceLayoutSessionStore = workspaceLayoutSessionStore
        self.workspaceRuntimeStore = workspaceRuntimeStore
    }

    var sessionLifecycleController: WorkspaceSessionLifecycleController {
        let sessionCreator = WorkspaceSessionCreator(
            documentSessionStore: documentSessionStore,
            terminalSessionController: terminalSessionController,
            previewSessionStore: previewSessionStore,
            workspaceSessionStore: workspaceSessionStore,
            previewRenderCoordinator: previewRenderCoordinator
        )
        let panelAttacher = WorkspaceSessionPanelAttacher(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceSessionStore: workspaceSessionStore
        )

        return WorkspaceSessionLifecycleController(
            workspaceStore: workspaceStore,
            panelAttacher: panelAttacher,
            sessionCreator: sessionCreator,
            terminalSessionController: terminalSessionController,
            previewSessionStore: previewSessionStore,
            workspaceSessionStore: workspaceSessionStore
        )
    }

    func openWorkspace(rootURL: URL) async throws {
        guard let workspaceStore else {
            throw WorkspaceCoordinatorError.missingWorkspaceStore
        }

        guard !workspaceStore.isOpeningWorkspace else {
            throw WorkspaceCoordinatorError.workspaceOpenInProgress
        }

        workspaceStore.clearOpenError()
        workspaceStore.isOpeningWorkspace = true
        defer {
            workspaceStore.isOpeningWorkspace = false
        }

        do {
            if let activeWorkspace = workspaceStore.activeWorkspace {
                if workspaceIDsPendingSnapshotRetry.contains(activeWorkspace.id) {
                    if hasRuntimeSessions(in: activeWorkspace.id) {
                        parkActiveWorkspaceRuntime()
                    }
                } else {
                    parkActiveWorkspaceRuntime()
                    try await saveSnapshot(for: activeWorkspace)
                }
                stopDocumentWatchers(in: activeWorkspace.id)
            }
        } catch {
            workspaceStore.openErrorMessage = error.localizedDescription
            throw error
        }

        let existingWorkspace = workspaceStore.workspaces.first {
            $0.rootURL.standardizedFileURL == rootURL.standardizedFileURL
        }
        let parkedRuntimeState = existingWorkspace.flatMap { workspace in
            workspaceRuntimeStore?.state(for: workspace.id)
        }
        let existingRuntimeState = existingWorkspace.flatMap { workspace -> WorkspaceRuntimeState? in
            guard !workspaceIDsPendingSnapshotRetry.contains(workspace.id) else {
                return nil
            }

            return parkedRuntimeState
        }
        let snapshot: WorkspaceSnapshot?
        var didFailSnapshotLoad = false
        if existingRuntimeState == nil {
            do {
                snapshot = try await workspaceRepository?.loadSnapshot(for: rootURL)
            } catch {
                snapshot = nil
                didFailSnapshotLoad = true
                workspaceStore.openErrorMessage = "Failed to restore workspace state: \(error.localizedDescription)"
            }
        } else {
            snapshot = nil
        }

        let previousWorkspaceID = existingWorkspace?.id
        let previousWorkspaceWasPendingRetry = previousWorkspaceID.map {
            workspaceIDsPendingSnapshotRetry.contains($0)
        } ?? false
        let gitBranch = await currentGitBranch(for: rootURL)
        let workspace = Workspace.make(
            id: snapshot?.workspaceID ?? previousWorkspaceID ?? Workspace.ID(),
            rootURL: rootURL,
            displayName: existingWorkspace?.displayName,
            securityBookmark: snapshot?.rootBookmark ?? existingWorkspace?.securityBookmark,
            gitBranch: gitBranch,
            panelRootID: snapshot?.panelTree?.id ?? existingWorkspace?.panelRootID,
            openedAt: existingWorkspace?.openedAt ?? Date()
        )

        var runtimeStateToRestore = existingRuntimeState
        if didFailSnapshotLoad {
            workspaceIDsPendingSnapshotRetry.insert(workspace.id)
            if previousWorkspaceWasPendingRetry {
                runtimeStateToRestore = parkedRuntimeState
            }
        } else {
            if let previousWorkspaceID {
                if previousWorkspaceWasPendingRetry {
                    runtimeStateToRestore = migratePendingWorkspaceRuntime(
                        from: previousWorkspaceID,
                        to: workspace.id
                    )
                }

                workspaceIDsPendingSnapshotRetry.remove(previousWorkspaceID)

                if previousWorkspaceID != workspace.id {
                    workspaceStore.closeWorkspace(id: previousWorkspaceID)
                    if runtimeStateToRestore == nil {
                        cleanupClosedWorkspaceRuntime(id: previousWorkspaceID)
                    } else {
                        cleanupClosedWorkspaceMetadata(id: previousWorkspaceID)
                    }
                }
            }

            workspaceIDsPendingSnapshotRetry.remove(workspace.id)
        }

        workspaceStore.setActiveWorkspace(workspace)
        restoreWorkspaceState(
            workspaceID: workspace.id,
            runtimeState: runtimeStateToRestore,
            snapshot: snapshot,
            shouldParkRestoredSnapshot: !didFailSnapshotLoad
        )

        if let activeWorkspace = workspaceStore.activeWorkspace {
            recentWorkspaceStore?.noteOpened(activeWorkspace)
        }
    }

    func closeWorkspace(id: Workspace.ID) async {
        guard let workspaceStore else {
            return
        }

        if let workspace = workspaceStore.workspaces.first(where: { $0.id == id }),
           shouldSaveSnapshotBeforeClosing(workspaceID: id) {
            do {
                try await saveSnapshot(for: workspace)
            } catch {
                workspaceStore.openErrorMessage = "Failed to close workspace: \(error.localizedDescription)"
                return
            }
        }

        let wasActiveWorkspace = workspaceStore.activeWorkspace?.id == id
        workspaceStore.closeWorkspace(id: id)
        cleanupClosedWorkspaceRuntime(id: id)

        if wasActiveWorkspace {
            restoreActiveWorkspaceAfterClose()
        }
    }

    func openDocument(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        replacingPanel panelID: PanelNode.ID?
    ) async throws {
        try await sessionLifecycleController.openDocument(
            url,
            preferredSurface: preferredSurface,
            replacingPanel: panelID
        )
        persistActiveLayoutSessionPanelState()
    }

    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws {
        try await sessionLifecycleController.openDocumentInNewPanel(
            url,
            preferredSurface: preferredSurface,
            splitDirection: splitDirection
        )
        persistActiveLayoutSessionPanelState()
    }

    func createTerminal(in workspaceID: Workspace.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: nil)
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: Optional(panelID))
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID?) async throws {
        try await sessionLifecycleController.createTerminal(in: workspaceID, replacingPanel: panelID)
        persistActiveLayoutSessionPanelState()
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelStore?.splitFocusedPanel(direction: direction, surface: surface)
        persistActiveLayoutSessionPanelState()
    }

    func createLayoutSession() {
        guard let workspaceID = workspaceStore?.activeWorkspace?.id,
              let panelStore,
              let workspaceLayoutSessionStore else {
            return
        }

        persistActiveLayoutSessionPanelState()
        let session = workspaceLayoutSessionStore.createSession(
            in: workspaceID,
            panelTree: .leaf(surface: .empty)
        )
        panelStore.reset(to: session.panelTree)
        if let focusedPanelID = session.focusedPanelID {
            panelStore.focus(panelID: focusedPanelID)
        }
        persistActiveLayoutSessionPanelState()
    }

    func selectLayoutSession(id sessionID: WorkspaceLayoutSession.ID) {
        guard let panelStore,
              let workspaceLayoutSessionStore,
              let session = workspaceLayoutSessionStore.session(for: sessionID),
              workspaceStore?.activeWorkspace?.id == session.workspaceID else {
            return
        }

        persistActiveLayoutSessionPanelState()
        workspaceLayoutSessionStore.activateSession(id: session.id)
        panelStore.reset(to: session.panelTree)
        if let focusedPanelID = session.focusedPanelID {
            panelStore.focus(panelID: focusedPanelID)
        }
    }

    func closeLayoutSession(id sessionID: WorkspaceLayoutSession.ID) {
        guard let panelStore,
              let workspaceLayoutSessionStore,
              let session = workspaceLayoutSessionStore.session(for: sessionID),
              workspaceStore?.activeWorkspace?.id == session.workspaceID else {
            return
        }

        let wasActiveSession = workspaceLayoutSessionStore.activeSessionID(in: session.workspaceID) == sessionID
        for workspaceSessionID in session.panelTree.workspaceSessionIDs {
            sessionLifecycleController.closeSession(id: workspaceSessionID)
        }
        _ = workspaceLayoutSessionStore.removeSession(id: sessionID)

        if workspaceLayoutSessionStore.sessions(in: session.workspaceID).isEmpty {
            _ = workspaceLayoutSessionStore.createSession(in: session.workspaceID)
        }

        if wasActiveSession,
           let activeSession = workspaceLayoutSessionStore.activeSession(in: session.workspaceID) {
            panelStore.reset(to: activeSession.panelTree)
            if let focusedPanelID = activeSession.focusedPanelID {
                panelStore.focus(panelID: focusedPanelID)
            }
        }

        persistActiveLayoutSessionPanelState()
    }

    private func saveSnapshot(for workspace: Workspace) async throws {
        persistActiveLayoutSessionPanelState(workspaceID: workspace.id)
        let documents = documentSessionStore?.snapshotSessions(in: workspace.id) ?? []
        let documentIDs = Set(documents.map(\.id))
        let runtimeState = workspaceRuntimeStore?.state(for: workspace.id)
        let isActiveWorkspace = workspaceStore?.activeWorkspace?.id == workspace.id
        let panelTree = isActiveWorkspace ? panelStore?.rootNode : runtimeState?.panelTree
        let focusedPanelID = isActiveWorkspace ? panelStore?.focusedPanelID : runtimeState?.focusedPanelID
        let layoutSessions = workspaceLayoutSessionStore?.snapshotSessions(in: workspace.id)
        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            panelTree: panelTree,
            layoutSessions: layoutSessions,
            activeLayoutSessionID: workspaceLayoutSessionStore?.activeSessionID(in: workspace.id),
            workspaceSessions: workspaceSessionStore?.snapshotSessions(in: workspace.id),
            sessions: terminalSessionController?.snapshotSessions(in: workspace.id) ?? [],
            documents: documents,
            previews: previewSessionStore?.snapshotStates(sourceDocumentIDs: documentIDs) ?? [],
            leftRailState: LeftRailState.default(
                workspaceID: workspace.id,
                panelID: focusedPanelID ?? panelTree?.firstLeafID
            )
        )
        try await workspaceRepository?.saveSnapshot(snapshot, for: workspace.rootURL)
    }

    private func shouldSaveSnapshotBeforeClosing(workspaceID: Workspace.ID) -> Bool {
        let isActiveWorkspace = workspaceStore?.activeWorkspace?.id == workspaceID
        let hasRuntimeState = workspaceRuntimeStore?.state(for: workspaceID) != nil

        return !workspaceIDsPendingSnapshotRetry.contains(workspaceID)
            && (isActiveWorkspace || hasRuntimeState)
    }

    private func restoreWorkspaceState(
        workspaceID: Workspace.ID,
        runtimeState: WorkspaceRuntimeState?,
        snapshot: WorkspaceSnapshot?,
        shouldParkRestoredSnapshot: Bool
    ) {
        if let runtimeState {
            restoreRuntimeState(runtimeState)
            return
        }

        restoreSnapshotState(snapshot, workspaceID: workspaceID)

        if let panelStore {
            workspaceLayoutSessionStore?.replaceSessions(
                in: workspaceID,
                with: snapshot?.layoutSessions ?? [],
                activeSessionID: snapshot?.activeLayoutSessionID,
                fallbackPanelTree: snapshot?.panelTree ?? .placeholder,
                fallbackFocusedPanelID: snapshot?.leftRailState.selectedPanelID
            )
            let activeLayoutSession = workspaceLayoutSessionStore?.activeSession(in: workspaceID)
            let panelTree = activeLayoutSession?.panelTree ?? snapshot?.panelTree ?? .placeholder
            panelStore.reset(to: panelTree)

            if let selectedPanelID = activeLayoutSession?.focusedPanelID ?? snapshot?.leftRailState.selectedPanelID {
                panelStore.focus(panelID: selectedPanelID)
            }

            if shouldParkRestoredSnapshot {
                workspaceRuntimeStore?.park(
                    workspaceID: workspaceID,
                    activeLayoutSessionID: workspaceLayoutSessionStore?.activeSessionID(in: workspaceID),
                    panelTree: panelStore.rootNode,
                    focusedPanelID: panelStore.focusedPanelID
                )
            }
        }
    }

    private func restoreRuntimeState(_ runtimeState: WorkspaceRuntimeState) {
        if let activeLayoutSessionID = runtimeState.activeLayoutSessionID {
            workspaceLayoutSessionStore?.activateSession(id: activeLayoutSessionID)
        } else {
            workspaceLayoutSessionStore?.ensureActiveSession(
                in: runtimeState.workspaceID,
                panelTree: runtimeState.panelTree,
                focusedPanelID: runtimeState.focusedPanelID
            )
        }

        let activeLayoutSession = workspaceLayoutSessionStore?.activeSession(in: runtimeState.workspaceID)
        panelStore?.reset(to: activeLayoutSession?.panelTree ?? runtimeState.panelTree)

        if let focusedPanelID = activeLayoutSession?.focusedPanelID ?? runtimeState.focusedPanelID {
            panelStore?.focus(panelID: focusedPanelID)
        }
    }

    private func restoreSnapshotState(_ snapshot: WorkspaceSnapshot?, workspaceID: Workspace.ID) {
        let previousDocumentIDs = Set(documentSessionStore?.snapshotSessions(in: workspaceID).map(\.id) ?? [])
        let restoredDocuments = snapshot?.documents ?? []
        let restoredDocumentIDs = Set(restoredDocuments.map(\.id))
        let affectedDocumentIDs = previousDocumentIDs.union(restoredDocumentIDs)

        stopDocumentWatchers(for: affectedDocumentIDs)
        documentTextStore?.removeSnapshots(for: affectedDocumentIDs)
        documentSessionStore?.replaceSessions(in: workspaceID, with: restoredDocuments)
        previewSessionStore?.replaceStates(
            forSourceDocumentIDs: affectedDocumentIDs,
            with: snapshot?.previews ?? []
        )
        terminalSessionController?.replaceSnapshotSessions(snapshot?.sessions ?? [], in: workspaceID)
        workspaceSessionStore?.replaceSessions(in: workspaceID, with: snapshot?.workspaceSessions ?? [])
    }

    private func parkActiveWorkspaceRuntime() {
        guard let workspaceID = workspaceStore?.activeWorkspace?.id, let panelStore else {
            return
        }

        persistActiveLayoutSessionPanelState(workspaceID: workspaceID)
        workspaceRuntimeStore?.park(
            workspaceID: workspaceID,
            activeLayoutSessionID: workspaceLayoutSessionStore?.activeSessionID(in: workspaceID),
            panelTree: panelStore.rootNode,
            focusedPanelID: panelStore.focusedPanelID
        )
    }

    private func cleanupClosedWorkspaceRuntime(id workspaceID: Workspace.ID) {
        let documentIDs = Set(documentSessionStore?.snapshotSessions(in: workspaceID).map(\.id) ?? [])

        stopDocumentWatchers(for: documentIDs)
        terminalSessionController?.removeSessions(in: workspaceID)
        previewSessionStore?.removeStates(forSourceDocumentIDs: documentIDs)
        documentSessionStore?.removeSessions(in: workspaceID)
        documentTextStore?.removeSnapshots(for: documentIDs)
        workspaceSessionStore?.removeSessions(in: workspaceID)
        workspaceLayoutSessionStore?.removeSessions(in: workspaceID)
        workspaceRuntimeStore?.removeState(for: workspaceID)
        workspaceIDsPendingSnapshotRetry.remove(workspaceID)
    }

    private func cleanupClosedWorkspaceMetadata(id workspaceID: Workspace.ID) {
        workspaceRuntimeStore?.removeState(for: workspaceID)
        workspaceIDsPendingSnapshotRetry.remove(workspaceID)
    }

    private func migratePendingWorkspaceRuntime(
        from sourceWorkspaceID: Workspace.ID,
        to targetWorkspaceID: Workspace.ID
    ) -> WorkspaceRuntimeState? {
        guard hasRuntimeSessions(in: sourceWorkspaceID) else {
            return nil
        }

        let runtimeState = runtimeStateForMigration(
            from: sourceWorkspaceID,
            to: targetWorkspaceID
        )

        terminalSessionController?.moveSessions(
            from: sourceWorkspaceID,
            to: targetWorkspaceID
        )
        documentSessionStore?.moveSessions(
            from: sourceWorkspaceID,
            to: targetWorkspaceID
        )
        workspaceSessionStore?.moveSessions(
            from: sourceWorkspaceID,
            to: targetWorkspaceID
        )
        workspaceLayoutSessionStore?.moveSessions(
            from: sourceWorkspaceID,
            to: targetWorkspaceID
        )

        if let runtimeState {
            workspaceRuntimeStore?.park(
                workspaceID: targetWorkspaceID,
                activeLayoutSessionID: runtimeState.activeLayoutSessionID,
                panelTree: runtimeState.panelTree,
                focusedPanelID: runtimeState.focusedPanelID
            )
        }
        if sourceWorkspaceID != targetWorkspaceID {
            workspaceRuntimeStore?.removeState(for: sourceWorkspaceID)
        }

        return runtimeState
    }

    private func runtimeStateForMigration(
        from sourceWorkspaceID: Workspace.ID,
        to targetWorkspaceID: Workspace.ID
    ) -> WorkspaceRuntimeState? {
        if workspaceStore?.activeWorkspace?.id == sourceWorkspaceID, let panelStore {
            return WorkspaceRuntimeState(
                workspaceID: targetWorkspaceID,
                activeLayoutSessionID: workspaceLayoutSessionStore?.activeSessionID(in: sourceWorkspaceID),
                panelTree: panelStore.rootNode,
                focusedPanelID: panelStore.focusedPanelID
            )
        }

        return workspaceRuntimeStore?.moveState(
            from: sourceWorkspaceID,
            to: targetWorkspaceID
        ) ?? workspaceSessionStore?.snapshotSessions(in: sourceWorkspaceID).first.map { session in
            WorkspaceRuntimeState(
                workspaceID: targetWorkspaceID,
                panelTree: .leaf(surface: .session(sessionID: session.id)),
                focusedPanelID: nil
            )
        }
    }

    private func hasRuntimeSessions(in workspaceID: Workspace.ID) -> Bool {
        if terminalSessionController?.snapshotSessions(in: workspaceID).isEmpty == false {
            return true
        }

        if documentSessionStore?.snapshotSessions(in: workspaceID).isEmpty == false {
            return true
        }

        if workspaceLayoutSessionStore?.snapshotSessions(in: workspaceID).isEmpty == false {
            return true
        }

        return workspaceSessionStore?.snapshotSessions(in: workspaceID).isEmpty == false
    }

    private func stopDocumentWatchers(in workspaceID: Workspace.ID) {
        let documentIDs = Set(documentSessionStore?.snapshotSessions(in: workspaceID).map(\.id) ?? [])
        stopDocumentWatchers(for: documentIDs)
    }

    private func stopDocumentWatchers(for documentIDs: Set<DocumentSession.ID>) {
        for documentID in documentIDs {
            documentFileWatchStore?.stopWatching(documentID: documentID)
        }
    }

    private func restoreActiveWorkspaceAfterClose() {
        guard let activeWorkspace = workspaceStore?.activeWorkspace else {
            panelStore?.reset(to: .placeholder)
            return
        }

        if let runtimeState = workspaceRuntimeStore?.state(for: activeWorkspace.id) {
            restoreRuntimeState(runtimeState)
        } else {
            let activeLayoutSession = workspaceLayoutSessionStore?.ensureActiveSession(in: activeWorkspace.id)
            panelStore?.reset(to: activeLayoutSession?.panelTree ?? .placeholder)
            if let focusedPanelID = activeLayoutSession?.focusedPanelID {
                panelStore?.focus(panelID: focusedPanelID)
            }
        }
    }

    func persistActiveLayoutSessionPanelState() {
        guard let workspaceID = workspaceStore?.activeWorkspace?.id else {
            return
        }

        persistActiveLayoutSessionPanelState(workspaceID: workspaceID)
    }

    private func persistActiveLayoutSessionPanelState(workspaceID: Workspace.ID) {
        guard workspaceStore?.activeWorkspace?.id == workspaceID,
              let panelStore else {
            return
        }

        workspaceLayoutSessionStore?.updateActiveSession(
            in: workspaceID,
            panelTree: panelStore.rootNode,
            focusedPanelID: panelStore.focusedPanelID
        )
    }

    private func currentGitBranch(for rootURL: URL) async -> String? {
        switch await gitBranchProvider.currentBranch(for: rootURL) {
        case let .branch(branch):
            return branch
        case .noBranch, .lookupFailed:
            return nil
        }
    }

}

enum WorkspaceCoordinatorError: LocalizedError, Equatable {
    case missingWorkspaceStore
    case missingActiveWorkspace
    case workspaceNotFound
    case workspaceOpenInProgress

    var errorDescription: String? {
        switch self {
        case .missingWorkspaceStore:
            return "Workspace store is not configured."
        case .missingActiveWorkspace:
            return "No workspace is currently active."
        case .workspaceNotFound:
            return "Workspace was not found."
        case .workspaceOpenInProgress:
            return "A workspace is already being opened."
        }
    }
}
