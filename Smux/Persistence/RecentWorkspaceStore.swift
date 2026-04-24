import Combine
import Foundation

struct RecentWorkspace: Identifiable, Codable, Hashable {
    var id: Workspace.ID
    var rootURL: URL
    var displayName: String
    var lastOpenedAt: Date
}

@MainActor
final class RecentWorkspaceStore: ObservableObject {
    @Published var recentWorkspaces: [RecentWorkspace] = []

    func noteOpened(_ workspace: Workspace) {}

    func remove(id: Workspace.ID) {}
}
