import Foundation

struct WorkspaceSnapshot: Codable, Hashable {
    var schemaVersion: Int
    var workspaceID: Workspace.ID
    var rootBookmark: Data?
    var panelTree: PanelNode?
    var sessions: [TerminalSession]
    var documents: [DocumentSession]
    var previews: [PreviewState]
    var leftRailState: LeftRailState
}

struct LeftRailState: Codable, Hashable {
    var selectedWorkspaceID: Workspace.ID?
    var selectedPanelID: PanelNode.ID?
    var isFileTreeVisible: Bool
}
