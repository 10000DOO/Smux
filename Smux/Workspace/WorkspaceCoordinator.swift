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
        previewSessionStore: PreviewSessionStore? = nil
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

    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {
        let documentID = try createDocumentSession(for: url)

        switch preferredSurface {
        case .editor:
            panelStore?.replaceFocusedPanel(with: .editor(documentID: documentID))
        case .preview:
            panelStore?.replaceFocusedPanel(with: createPreviewSurface(sourceDocumentID: documentID))
        case .split:
            panelStore?.replaceFocusedPanel(with: .editor(documentID: documentID))
            panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: createPreviewSurface(sourceDocumentID: documentID)
            )
        }
    }

    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws {
        let documentID = try createDocumentSession(for: url)

        switch preferredSurface {
        case .editor:
            panelStore?.splitFocusedPanel(direction: splitDirection, surface: .editor(documentID: documentID))
        case .preview:
            panelStore?.splitFocusedPanel(
                direction: splitDirection,
                surface: createPreviewSurface(sourceDocumentID: documentID)
            )
        case .split:
            panelStore?.splitFocusedPanel(direction: splitDirection, surface: .editor(documentID: documentID))
            panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: createPreviewSurface(sourceDocumentID: documentID)
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
            replacePanel(with: .terminal(sessionID: TerminalSession.ID()), preferredPanelID: panelID)
            return
        }

        replacePanel(with: .terminal(sessionID: session.id), preferredPanelID: panelID)
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelStore?.splitFocusedPanel(direction: direction, surface: surface)
    }

    private func saveSnapshot(for workspace: Workspace) async throws {
        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            panelTree: panelStore?.rootNode,
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
    }

    private func currentGitBranch(for rootURL: URL) async -> String? {
        switch await gitBranchProvider.currentBranch(for: rootURL) {
        case let .branch(branch):
            return branch
        case .noBranch, .lookupFailed:
            return nil
        }
    }

    private func createDocumentSession(for url: URL) throws -> DocumentSession.ID {
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

        return documentID
    }

    private func createPreviewSurface(sourceDocumentID documentID: DocumentSession.ID) -> PanelSurfaceDescriptor {
        let previewID = PreviewState.ID()
        previewSessionStore?.bind(previewID: previewID, sourceDocumentID: documentID)
        return .preview(previewID: previewID)
    }

    private func replacePanel(with surface: PanelSurfaceDescriptor, preferredPanelID panelID: PanelNode.ID?) {
        if let panelID, panelStore?.rootNode.containsLeaf(panelID: panelID) == true {
            panelStore?.replacePanel(panelID: panelID, with: surface)
            return
        }

        panelStore?.replaceFocusedPanel(with: surface)
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
