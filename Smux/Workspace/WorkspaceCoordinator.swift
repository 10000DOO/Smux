import Foundation

@MainActor
final class WorkspaceCoordinator: WorkspaceOpening, DocumentOpening, TerminalCommanding, PanelCommanding {
    var workspaceStore: WorkspaceStore?
    var panelStore: PanelStore?
    var workspaceRepository: (any WorkspaceRepository)?
    var recentWorkspaceStore: RecentWorkspaceStore?
    var documentSessionStore: DocumentSessionStore?
    var terminalSessionController: TerminalSessionController?
    var previewSessionStore: PreviewSessionStore?

    init(
        workspaceStore: WorkspaceStore? = nil,
        panelStore: PanelStore? = nil,
        workspaceRepository: (any WorkspaceRepository)? = nil,
        recentWorkspaceStore: RecentWorkspaceStore? = nil,
        documentSessionStore: DocumentSessionStore? = nil,
        terminalSessionController: TerminalSessionController? = nil,
        previewSessionStore: PreviewSessionStore? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.workspaceRepository = workspaceRepository
        self.recentWorkspaceStore = recentWorkspaceStore
        self.documentSessionStore = documentSessionStore
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
        let workspace = Workspace.make(
            id: snapshot?.workspaceID ?? existingWorkspace?.id ?? Workspace.ID(),
            rootURL: rootURL,
            displayName: existingWorkspace?.displayName,
            securityBookmark: snapshot?.rootBookmark ?? existingWorkspace?.securityBookmark,
            gitBranch: existingWorkspace?.gitBranch,
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

        workspaceStore.closeWorkspace(id: id)
    }

    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {
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

        switch preferredSurface {
        case .editor:
            panelStore?.replaceFocusedPanel(with: .editor(documentID: documentID))
        case .preview:
            let previewID = PreviewState.ID()
            previewSessionStore?.bind(previewID: previewID, sourceDocumentID: documentID)
            panelStore?.replaceFocusedPanel(with: .preview(previewID: previewID))
        case .split:
            let previewID = PreviewState.ID()
            previewSessionStore?.bind(previewID: previewID, sourceDocumentID: documentID)
            panelStore?.replaceFocusedPanel(with: .editor(documentID: documentID))
            panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: .preview(previewID: previewID)
            )
        }
    }

    func createTerminal(in workspaceID: Workspace.ID) async throws {
        guard let workspace = workspaceStore?.workspaces.first(where: { $0.id == workspaceID }) else {
            throw WorkspaceCoordinatorError.workspaceNotFound
        }

        guard let session = try await terminalSessionController?.createSession(in: workspace, command: []) else {
            panelStore?.replaceFocusedPanel(with: .terminal(sessionID: TerminalSession.ID()))
            return
        }

        panelStore?.replaceFocusedPanel(with: .terminal(sessionID: session.id))
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
        documentSessionStore?.replaceSessions(snapshot?.documents ?? [])
        previewSessionStore?.replaceStates(snapshot?.previews ?? [])
        terminalSessionController?.replaceSnapshotSessions(snapshot?.sessions ?? [])
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
