import Combine
import Foundation

@MainActor
final class FileTreeStore: ObservableObject {
    @Published var root: FileTreeNode?
    @Published var selectedNodeID: FileTreeNode.ID?
    @Published var filterText = ""

    private let loader: FileTreeLoading

    init(loader: FileTreeLoading = FileManagerFileTreeLoader()) {
        self.loader = loader
    }

    func loadRoot(rootURL: URL) async throws {
        let loadedRoot = try await loader.loadRoot(at: rootURL)
        try Task.checkCancellation()
        root = loadedRoot
        selectedNodeID = nil
    }

    func loadRoot(workspace: Workspace) async throws {
        try await loadRoot(rootURL: workspace.rootURL)
    }

    func loadRoot(workspaceID: Workspace.ID) async throws {
        throw FileTreeStoreError.workspaceRootUnavailable(workspaceID)
    }

    func expand(nodeID: FileTreeNode.ID) async throws {
        guard let targetNode = root?.node(id: nodeID) else {
            throw FileTreeStoreError.nodeNotFound(nodeID)
        }

        guard targetNode.kind == .directory else {
            return
        }

        switch targetNode.childrenState {
        case .loaded, .loading:
            return
        case .notLoaded, .failed:
            root = root?.replacingChildrenState(for: nodeID, with: .loading)

            do {
                let children = try await loader.loadChildren(of: targetNode.url)
                root = root?.replacingChildrenState(for: nodeID, with: .loaded(children))
            } catch {
                root = root?.replacingChildrenState(
                    for: nodeID,
                    with: .failed(message: error.localizedDescription)
                )
                throw error
            }
        }
    }

    func clear() {
        root = nil
        selectedNodeID = nil
        filterText = ""
    }
}

nonisolated enum FileTreeStoreError: LocalizedError {
    case workspaceRootUnavailable(Workspace.ID)
    case nodeNotFound(FileTreeNode.ID)

    var errorDescription: String? {
        switch self {
        case .workspaceRootUnavailable(let workspaceID):
            return "Workspace root URL is unavailable for workspace \(workspaceID.uuidString)."
        case .nodeNotFound(let nodeID):
            return "File tree node \(nodeID.uuidString) was not found."
        }
    }
}

private extension FileTreeNode {
    func node(id targetID: ID) -> FileTreeNode? {
        if id == targetID {
            return self
        }

        guard case .loaded(let children) = childrenState else {
            return nil
        }

        for child in children {
            if let matchingNode = child.node(id: targetID) {
                return matchingNode
            }
        }

        return nil
    }

    func replacingChildrenState(
        for targetID: ID,
        with replacementChildrenState: FileTreeChildrenState
    ) -> FileTreeNode {
        if id == targetID {
            var node = self
            node.childrenState = replacementChildrenState
            return node
        }

        guard case .loaded(let children) = childrenState else {
            return self
        }

        var node = self
        node.childrenState = .loaded(
            children.map {
                $0.replacingChildrenState(for: targetID, with: replacementChildrenState)
            }
        )
        return node
    }
}
