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
}

@MainActor
protocol TerminalCommanding {
    func createTerminal(in workspaceID: Workspace.ID) async throws
}

@MainActor
protocol PanelCommanding {
    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor)
}
