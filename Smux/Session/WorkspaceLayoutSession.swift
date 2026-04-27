import Foundation

nonisolated struct WorkspaceLayoutSession: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var title: String
    var panelTree: PanelNode
    var focusedPanelID: PanelNode.ID?
    var createdAt: Date
    var lastActiveAt: Date

    init(
        id: ID = ID(),
        workspaceID: Workspace.ID,
        title: String,
        panelTree: PanelNode = .leaf(surface: .empty),
        focusedPanelID: PanelNode.ID? = nil,
        createdAt: Date = Date(),
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.panelTree = panelTree
        self.focusedPanelID = focusedPanelID ?? panelTree.firstLeafID
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt ?? createdAt
    }
}
