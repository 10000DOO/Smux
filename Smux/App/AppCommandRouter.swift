import Foundation

@MainActor
struct AppCommandRouter {
    var workspaceOpening: (any WorkspaceOpening)?
    var documentOpening: (any DocumentOpening)?
    var terminalCommanding: (any TerminalCommanding)?
    var panelCommanding: (any PanelCommanding)?

    func openWorkspace(rootURL: URL) async throws {
        guard let workspaceOpening else {
            throw AppCommandRouterError.missingWorkspaceOpening
        }

        try await workspaceOpening.openWorkspace(rootURL: rootURL)
    }

    func closeWorkspace(id: Workspace.ID) async throws {
        guard let workspaceOpening else {
            throw AppCommandRouterError.missingWorkspaceOpening
        }

        await workspaceOpening.closeWorkspace(id: id)
    }

    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {
        guard let documentOpening else {
            throw AppCommandRouterError.missingDocumentOpening
        }

        try await documentOpening.openDocument(url, preferredSurface: preferredSurface)
    }

    func createTerminal(in workspaceID: Workspace.ID) async throws {
        guard let terminalCommanding else {
            throw AppCommandRouterError.missingTerminalCommanding
        }

        try await terminalCommanding.createTerminal(in: workspaceID)
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID) async throws {
        guard let terminalCommanding else {
            throw AppCommandRouterError.missingTerminalCommanding
        }

        try await terminalCommanding.createTerminal(in: workspaceID, replacingPanel: Optional(panelID))
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelCommanding?.splitFocusedPanel(direction: direction, surface: surface)
    }

    func focusNextPanel() {
        panelCommanding?.focusNextPanel()
    }

    func focusPreviousPanel() {
        panelCommanding?.focusPreviousPanel()
    }
}

enum AppCommandRouterError: Error, Equatable {
    case missingWorkspaceOpening
    case missingDocumentOpening
    case missingTerminalCommanding
}
