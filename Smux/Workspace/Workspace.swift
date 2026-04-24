import Foundation

struct Workspace: Identifiable, Codable, Hashable {
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
