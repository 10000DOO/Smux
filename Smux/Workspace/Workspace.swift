import Foundation

nonisolated struct Workspace: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var rootURL: URL
    var displayName: String
    var securityBookmark: Data?
    var gitBranch: String?
    var panelRootID: PanelNode.ID?
    var openedAt: Date
    var lastActiveAt: Date
}

extension Workspace {
    static func make(
        id: ID = UUID(),
        rootURL: URL,
        displayName: String? = nil,
        securityBookmark: Data? = nil,
        gitBranch: String? = nil,
        panelRootID: PanelNode.ID? = nil,
        openedAt: Date = Date(),
        lastActiveAt: Date? = nil
    ) -> Workspace {
        Workspace(
            id: id,
            rootURL: rootURL,
            displayName: displayName ?? rootURL.lastPathComponent,
            securityBookmark: securityBookmark,
            gitBranch: gitBranch,
            panelRootID: panelRootID,
            openedAt: openedAt,
            lastActiveAt: lastActiveAt ?? openedAt
        )
    }

    func markingActive(at date: Date = Date()) -> Workspace {
        var workspace = self
        workspace.lastActiveAt = date
        return workspace
    }
}
