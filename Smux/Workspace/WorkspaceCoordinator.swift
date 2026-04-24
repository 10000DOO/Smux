import Foundation

@MainActor
final class WorkspaceCoordinator: WorkspaceOpening, DocumentOpening, TerminalCommanding, PanelCommanding {
    var workspaceStore: WorkspaceStore?
    var panelStore: PanelStore?
    var workspaceRepository: (any WorkspaceRepository)?

    init(
        workspaceStore: WorkspaceStore? = nil,
        panelStore: PanelStore? = nil,
        workspaceRepository: (any WorkspaceRepository)? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.workspaceRepository = workspaceRepository
    }

    func openWorkspace(rootURL: URL) async throws {}

    func closeWorkspace(id: Workspace.ID) async {}

    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {}

    func createTerminal(in workspaceID: Workspace.ID) async throws {}

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {}
}
