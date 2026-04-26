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

    func openDocument(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        replacingPanel panelID: PanelNode.ID?
    ) async throws {
        guard let documentOpening else {
            throw AppCommandRouterError.missingDocumentOpening
        }

        try await documentOpening.openDocument(
            url,
            preferredSurface: preferredSurface,
            replacingPanel: panelID
        )
    }

    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws {
        guard let documentOpening else {
            throw AppCommandRouterError.missingDocumentOpening
        }

        try await documentOpening.openDocumentInNewPanel(
            url,
            preferredSurface: preferredSurface,
            splitDirection: splitDirection
        )
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

    func focus(panelID: PanelNode.ID?) {
        panelCommanding?.focus(panelID: panelID)
    }

    func createPanel(splitDirection: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelCommanding?.createPanel(splitDirection: splitDirection, surface: surface)
    }

    func splitPanel(panelID: PanelNode.ID, direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelCommanding?.splitPanel(panelID: panelID, direction: direction, surface: surface)
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelCommanding?.splitFocusedPanel(direction: direction, surface: surface)
    }

    func updateSplitRatio(splitID: PanelNode.ID, ratio: Double) {
        panelCommanding?.updateSplitRatio(splitID: splitID, ratio: ratio)
    }

    func focusNextPanel() {
        panelCommanding?.focusNextPanel()
    }

    func focusPreviousPanel() {
        panelCommanding?.focusPreviousPanel()
    }

    func closeFocusedPanel() {
        panelCommanding?.closeFocusedPanel()
    }
}

enum AppCommandRouterError: Error, Equatable {
    case missingWorkspaceOpening
    case missingDocumentOpening
    case missingTerminalCommanding
}
