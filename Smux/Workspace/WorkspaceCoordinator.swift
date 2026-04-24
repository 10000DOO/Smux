import Foundation

@MainActor
final class WorkspaceCoordinator: WorkspaceOpening, DocumentOpening, TerminalCommanding, PanelCommanding {
    var workspaceStore: WorkspaceStore?
    var panelStore: PanelStore?
    var workspaceRepository: (any WorkspaceRepository)?
    var recentWorkspaceStore: RecentWorkspaceStore?

    init(
        workspaceStore: WorkspaceStore? = nil,
        panelStore: PanelStore? = nil,
        workspaceRepository: (any WorkspaceRepository)? = nil,
        recentWorkspaceStore: RecentWorkspaceStore? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.workspaceRepository = workspaceRepository
        self.recentWorkspaceStore = recentWorkspaceStore
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
        guard workspaceStore?.activeWorkspace != nil else {
            throw WorkspaceCoordinatorError.missingActiveWorkspace
        }

        let documentID = DocumentSession.ID()

        switch preferredSurface {
        case .editor:
            panelStore?.replaceFocusedPanel(with: .editor(documentID: documentID))
        case .preview:
            panelStore?.replaceFocusedPanel(with: .preview(previewID: PreviewState.ID()))
        case .split:
            panelStore?.replaceFocusedPanel(with: .editor(documentID: documentID))
            panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: .preview(previewID: PreviewState.ID())
            )
        }
    }

    func createTerminal(in workspaceID: Workspace.ID) async throws {
        guard workspaceStore?.workspaces.contains(where: { $0.id == workspaceID }) == true else {
            throw WorkspaceCoordinatorError.workspaceNotFound
        }

        panelStore?.replaceFocusedPanel(with: .terminal(sessionID: TerminalSession.ID()))
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelStore?.splitFocusedPanel(direction: direction, surface: surface)
    }

    private func saveSnapshot(for workspace: Workspace) async throws {
        let snapshot = WorkspaceSnapshot(workspace: workspace, panelTree: panelStore?.rootNode)
        try await workspaceRepository?.saveSnapshot(snapshot, for: workspace.rootURL)
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
