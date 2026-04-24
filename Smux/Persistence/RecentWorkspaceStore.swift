import Combine
import Foundation

nonisolated struct RecentWorkspace: Identifiable, Codable, Hashable {
    var id: Workspace.ID
    var rootURL: URL
    var displayName: String
    var lastOpenedAt: Date
}

@MainActor
final class RecentWorkspaceStore: ObservableObject {
    @Published var recentWorkspaces: [RecentWorkspace] = []

    func noteOpened(_ workspace: Workspace) {
        let rootURL = workspace.rootURL.standardizedFileURL

        recentWorkspaces.removeAll {
            $0.id == workspace.id || $0.rootURL.standardizedFileURL == rootURL
        }

        recentWorkspaces.insert(
            RecentWorkspace(
                id: workspace.id,
                rootURL: workspace.rootURL,
                displayName: workspace.displayName,
                lastOpenedAt: workspace.lastActiveAt
            ),
            at: 0
        )
    }

    func remove(id: Workspace.ID) {
        recentWorkspaces.removeAll { $0.id == id }
    }
}
