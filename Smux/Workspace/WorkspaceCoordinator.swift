import Foundation

@MainActor
final class WorkspaceCoordinator: WorkspaceOpening, DocumentOpening, TerminalCommanding, PanelCommanding {
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
    var workspaceSessionStore: WorkspaceSessionStore?

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
        workspaceSessionStore: WorkspaceSessionStore? = nil
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
        self.workspaceSessionStore = workspaceSessionStore
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
                try await saveSnapshot(for: activeWorkspace)
            }
        } catch {
            workspaceStore.openErrorMessage = error.localizedDescription
            throw error
        }

        let snapshot: WorkspaceSnapshot?
        do {
            snapshot = try await workspaceRepository?.loadSnapshot(for: rootURL)
        } catch {
            snapshot = nil
            workspaceStore.openErrorMessage = "Failed to restore workspace state: \(error.localizedDescription)"
        }

        let existingWorkspace = workspaceStore.workspaces.first {
            $0.rootURL.standardizedFileURL == rootURL.standardizedFileURL
        }
        let gitBranch = await currentGitBranch(for: rootURL)
        let workspace = Workspace.make(
            id: snapshot?.workspaceID ?? existingWorkspace?.id ?? Workspace.ID(),
            rootURL: rootURL,
            displayName: existingWorkspace?.displayName,
            securityBookmark: snapshot?.rootBookmark ?? existingWorkspace?.securityBookmark,
            gitBranch: gitBranch,
            panelRootID: snapshot?.panelTree?.id ?? existingWorkspace?.panelRootID,
            openedAt: existingWorkspace?.openedAt ?? Date()
        )

        workspaceStore.setActiveWorkspace(workspace)
        restoreSnapshotState(snapshot)

        if let panelStore {
            let panelTree = snapshot?.panelTree ?? .placeholder
            panelStore.reset(to: panelTree)

            if let selectedPanelID = snapshot?.leftRailState.selectedPanelID {
                panelStore.focus(panelID: selectedPanelID)
            }
        }

        if let activeWorkspace = workspaceStore.activeWorkspace {
            recentWorkspaceStore?.noteOpened(activeWorkspace)
        }
    }

    func closeWorkspace(id: Workspace.ID) async {
        guard let workspaceStore else {
            return
        }

        if let activeWorkspace = workspaceStore.activeWorkspace, activeWorkspace.id == id {
            do {
                try await saveSnapshot(for: activeWorkspace)
            } catch {
                workspaceStore.openErrorMessage = "Failed to close workspace: \(error.localizedDescription)"
                return
            }
        }

        let wasActiveWorkspace = workspaceStore.activeWorkspace?.id == id
        workspaceStore.closeWorkspace(id: id)

        if wasActiveWorkspace {
            documentFileWatchStore?.stopAll()
            documentTextStore?.clearAll()
        }
    }

    func openDocument(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        replacingPanel panelID: PanelNode.ID?
    ) async throws {
        let editorSession = try createDocumentSession(for: url)

        switch preferredSurface {
        case .editor:
            replacePanel(with: .session(sessionID: editorSession.session.id), preferredPanelID: panelID)
        case .preview:
            replacePanel(with: createPreviewSurface(sourceDocumentID: editorSession.documentID), preferredPanelID: panelID)
        case .split:
            replacePanel(with: .session(sessionID: editorSession.session.id), preferredPanelID: panelID)
            panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: createPreviewSurface(sourceDocumentID: editorSession.documentID)
            )
        }
    }

    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws {
        let editorSession = try createDocumentSession(for: url)

        switch preferredSurface {
        case .editor:
            createPanel(splitDirection: splitDirection, surface: .session(sessionID: editorSession.session.id))
        case .preview:
            createPanel(splitDirection: splitDirection, surface: createPreviewSurface(sourceDocumentID: editorSession.documentID))
        case .split:
            createPanel(splitDirection: splitDirection, surface: .session(sessionID: editorSession.session.id))
            panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: createPreviewSurface(sourceDocumentID: editorSession.documentID)
            )
        }
    }

    func createTerminal(in workspaceID: Workspace.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: nil)
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: Optional(panelID))
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID?) async throws {
        guard let workspace = workspaceStore?.workspaces.first(where: { $0.id == workspaceID }) else {
            throw WorkspaceCoordinatorError.workspaceNotFound
        }

        guard let session = try await terminalSessionController?.createSession(in: workspace, command: []) else {
            let missingSession = WorkspaceSession(
                workspaceID: workspace.id,
                kind: .terminal,
                content: .terminal(TerminalSession.ID()),
                title: "Terminal",
                createdAt: Date()
            )
            workspaceSessionStore?.upsertSession(missingSession)
            replacePanel(with: .session(sessionID: missingSession.id), preferredPanelID: panelID)
            return
        }

        let workspaceSession = WorkspaceSession(terminal: session)
        workspaceSessionStore?.upsertSession(workspaceSession)
        replacePanel(with: .session(sessionID: workspaceSession.id), preferredPanelID: panelID)
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelStore?.splitFocusedPanel(direction: direction, surface: surface)
    }

    private func saveSnapshot(for workspace: Workspace) async throws {
        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            panelTree: panelStore?.rootNode,
            workspaceSessions: workspaceSessionStore?.snapshotSessions(),
            sessions: terminalSessionController?.snapshotSessions() ?? [],
            documents: documentSessionStore?.snapshotSessions() ?? [],
            previews: previewSessionStore?.snapshotStates() ?? []
        )
        try await workspaceRepository?.saveSnapshot(snapshot, for: workspace.rootURL)
    }

    private func restoreSnapshotState(_ snapshot: WorkspaceSnapshot?) {
        documentFileWatchStore?.stopAll()
        documentTextStore?.clearAll()
        documentSessionStore?.replaceSessions(snapshot?.documents ?? [])
        previewSessionStore?.replaceStates(snapshot?.previews ?? [])
        terminalSessionController?.replaceSnapshotSessions(snapshot?.sessions ?? [])
        workspaceSessionStore?.replaceSessions(snapshot?.workspaceSessions ?? [])
    }

    private func currentGitBranch(for rootURL: URL) async -> String? {
        switch await gitBranchProvider.currentBranch(for: rootURL) {
        case let .branch(branch):
            return branch
        case .noBranch, .lookupFailed:
            return nil
        }
    }

    private func createDocumentSession(for url: URL) throws -> (session: WorkspaceSession, documentID: DocumentSession.ID) {
        guard let workspace = workspaceStore?.activeWorkspace else {
            throw WorkspaceCoordinatorError.missingActiveWorkspace
        }

        let documentID = DocumentSession.ID()
        let session = DocumentSession.make(
            id: documentID,
            workspaceID: workspace.id,
            url: url
        )
        documentSessionStore?.upsertSession(session)
        let workspaceSession = WorkspaceSession(document: session)
        workspaceSessionStore?.upsertSession(workspaceSession)

        return (workspaceSession, documentID)
    }

    private func createPreviewSurface(sourceDocumentID documentID: DocumentSession.ID) -> PanelSurfaceDescriptor {
        guard let workspace = workspaceStore?.activeWorkspace else {
            return .empty
        }

        let previewID = PreviewState.ID()
        previewSessionStore?.bind(previewID: previewID, sourceDocumentID: documentID)
        let workspaceSession = WorkspaceSession(
            id: WorkspaceSession.ID(),
            workspaceID: workspace.id,
            kind: .preview,
            content: .preview(previewID: previewID, sourceDocumentID: documentID),
            title: "Preview",
            createdAt: Date()
        )
        workspaceSessionStore?.upsertSession(workspaceSession)
        return .session(sessionID: workspaceSession.id)
    }

    private func replacePanel(with surface: PanelSurfaceDescriptor, preferredPanelID panelID: PanelNode.ID?) {
        if let panelID, panelStore?.rootNode.containsLeaf(panelID: panelID) == true {
            let detachedSurface = panelStore?.rootNode.surface(forLeaf: panelID)
            panelStore?.replacePanel(panelID: panelID, with: surface)
            cleanupReplacedPanelSurface(detachedSurface, replacement: surface)
            return
        }

        let detachedSurface = panelStore?.focusedSurface
        panelStore?.replaceFocusedPanel(with: surface)
        cleanupReplacedPanelSurface(detachedSurface, replacement: surface)
    }

    private func cleanupReplacedPanelSurface(
        _ detachedSurface: PanelSurfaceDescriptor?,
        replacement: PanelSurfaceDescriptor
    ) {
        guard detachedSurface != replacement else {
            return
        }

        cleanupDetachedPanelSurface(detachedSurface)
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
