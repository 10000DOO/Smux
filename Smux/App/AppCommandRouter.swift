import Foundation

@MainActor
struct AppCommandRouter {
    var workspaceOpening: (any WorkspaceOpening)?
    var documentOpening: (any DocumentOpening)?
    var terminalCommanding: (any TerminalCommanding)?
    var panelCommanding: (any PanelCommanding)?

    func openWorkspace(rootURL: URL) async throws {}

    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {}

    func createTerminal(in workspaceID: Workspace.ID) async throws {}

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {}
}
