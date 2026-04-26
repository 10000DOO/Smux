import Foundation

enum DocumentOpenMode: String, Codable, Hashable {
    case editor
    case preview
    case split
}

@MainActor
protocol WorkspaceOpening {
    func openWorkspace(rootURL: URL) async throws
    func closeWorkspace(id: Workspace.ID) async
}

@MainActor
protocol DocumentOpening {
    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws
    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws
}

@MainActor
protocol TerminalCommanding {
    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID?) async throws
}

extension TerminalCommanding {
    func createTerminal(in workspaceID: Workspace.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: nil)
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: Optional(panelID))
    }
}

@MainActor
protocol PanelCommanding {
    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor)
    func focusNextPanel()
    func focusPreviousPanel()
}

extension WorkspaceCoordinator {
    func focusNextPanel() {
        panelStore?.focusNextPanel()
    }

    func focusPreviousPanel() {
        panelStore?.focusPreviousPanel()
    }
}
