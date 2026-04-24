import Foundation

nonisolated struct WorkspaceSnapshot: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var workspaceID: Workspace.ID
    var rootBookmark: Data?
    var panelTree: PanelNode?
    var sessions: [TerminalSession]
    var documents: [DocumentSession]
    var previews: [PreviewState]
    var leftRailState: LeftRailState
}

nonisolated struct LeftRailState: Codable, Hashable {
    var selectedWorkspaceID: Workspace.ID?
    var selectedPanelID: PanelNode.ID?
    var isFileTreeVisible: Bool
}

extension WorkspaceSnapshot {
    init(
        workspace: Workspace,
        panelTree: PanelNode?,
        sessions: [TerminalSession] = [],
        documents: [DocumentSession] = [],
        previews: [PreviewState] = [],
        leftRailState: LeftRailState? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.workspaceID = workspace.id
        self.rootBookmark = workspace.securityBookmark
        self.panelTree = panelTree
        self.sessions = sessions
        self.documents = documents
        self.previews = previews
        self.leftRailState = leftRailState ?? .default(
            workspaceID: workspace.id,
            panelID: panelTree?.firstLeafID
        )
    }
}

extension LeftRailState {
    static func `default`(
        workspaceID: Workspace.ID? = nil,
        panelID: PanelNode.ID? = nil
    ) -> LeftRailState {
        LeftRailState(
            selectedWorkspaceID: workspaceID,
            selectedPanelID: panelID,
            isFileTreeVisible: true
        )
    }
}
