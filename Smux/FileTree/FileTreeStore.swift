import Combine
import Foundation

@MainActor
final class FileTreeStore: ObservableObject {
    @Published var root: FileTreeNode?
    @Published var selectedNodeID: FileTreeNode.ID?
    @Published var filterText = ""

    func loadRoot(workspaceID: Workspace.ID) async throws {}

    func expand(nodeID: FileTreeNode.ID) async throws {}
}
