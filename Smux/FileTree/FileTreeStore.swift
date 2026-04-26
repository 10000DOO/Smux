import Combine
import Foundation

@MainActor
final class FileTreeStore: ObservableObject {
    @Published var root: FileTreeNode?
    @Published var selectedNodeID: FileTreeNode.ID?
    @Published var filterText = ""

    var selectedDocumentCandidateURL: URL? {
        guard let selectedNodeID,
              let node = root?.node(id: selectedNodeID),
              node.kind == .file,
              node.isDocumentCandidate
        else {
            return nil
        }

        return node.url
    }

    private let loader: FileTreeLoading
    private let watcher: FileWatching
    private let watchDebouncer: FileWatchDebouncer
    private var currentRootURL: URL?
    private var requestedRootURL: URL?
    private var rootLoadGeneration = 0
    private var reloadTask: Task<Void, Never>?

    init(
        loader: FileTreeLoading = FileManagerFileTreeLoader(),
        watcher: FileWatching = LocalFileWatcher(),
        fileWatchDebounceInterval: TimeInterval = 0.25
    ) {
        self.loader = loader
        self.watcher = watcher
        self.watchDebouncer = FileWatchDebouncer(interval: fileWatchDebounceInterval)

        watcher.eventHandler = { [weak watchDebouncer] events in
            events
                .filter { event in
                    if case .workspaceRoot = event.scope {
                        return true
                    }
                    return false
                }
                .forEach { watchDebouncer?.submit($0) }
        }

        watchDebouncer.eventHandler = { [weak self] events in
            Task { @MainActor [weak self] in
                self?.handleDebouncedWatchEvents(events)
            }
        }
    }

    deinit {
        reloadTask?.cancel()
        watchDebouncer.cancel()
        watcher.eventHandler = nil
        watcher.stopAll()
    }

    func loadRoot(rootURL: URL) async throws {
        try await loadRoot(rootURL: rootURL, resetSelection: true)
    }

    private func loadRoot(rootURL: URL, resetSelection: Bool) async throws {
        rootLoadGeneration += 1
        let loadGeneration = rootLoadGeneration
        requestedRootURL = rootURL

        let loadedRoot = try await loader.loadRoot(at: rootURL)
        try Task.checkCancellation()

        guard loadGeneration == rootLoadGeneration, requestedRootURL == rootURL else {
            throw CancellationError()
        }

        try startWatchingRoot(rootURL)

        root = loadedRoot
        currentRootURL = rootURL

        if resetSelection {
            selectedNodeID = nil
        }
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
        rootLoadGeneration += 1
        reloadTask?.cancel()
        reloadTask = nil
        watchDebouncer.cancel()
        stopWatchingCurrentRoot()
        requestedRootURL = nil
        root = nil
        selectedNodeID = nil
        filterText = ""
    }

    private func handleDebouncedWatchEvents(_ events: [FileWatchEvent]) {
        guard let currentRootURL else {
            return
        }

        guard events.contains(where: { event in
            event.scope == .workspaceRoot(currentRootURL)
        }) else {
            return
        }

        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self, currentRootURL] in
            do {
                try await self?.reloadCurrentRoot(rootURL: currentRootURL)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func reloadCurrentRoot(rootURL: URL) async throws {
        guard currentRootURL == rootURL, requestedRootURL == rootURL else {
            return
        }

        try await loadRoot(rootURL: rootURL, resetSelection: false)
    }

    private func startWatchingRoot(_ rootURL: URL) throws {
        let newScope = FileWatchScope.workspaceRoot(rootURL)

        if let currentRootURL {
            let currentScope = FileWatchScope.workspaceRoot(currentRootURL)

            guard currentScope != newScope else {
                return
            }

            try watcher.startWatching(newScope)
            watcher.stopWatching(currentScope)
            return
        }

        try watcher.startWatching(newScope)
    }

    private func stopWatchingCurrentRoot() {
        guard let currentRootURL else {
            return
        }

        watcher.stopWatching(.workspaceRoot(currentRootURL))
        self.currentRootURL = nil
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
