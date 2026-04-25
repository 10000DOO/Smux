import Foundation

nonisolated protocol FileTreeLoading {
    func loadRoot(at rootURL: URL) async throws -> FileTreeNode
    func loadChildren(of directoryURL: URL) async throws -> [FileTreeNode]
}

nonisolated enum FileTreeLoadingError: LocalizedError {
    case rootIsNotDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .rootIsNotDirectory(let url):
            return "\(url.path) is not a directory."
        }
    }
}

nonisolated struct FileManagerFileTreeLoader: FileTreeLoading {
    private static let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey]
    private static let documentExtensions: Set<String> = [
        "md",
        "markdown",
        "mmd",
        "mermaid",
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadRoot(at rootURL: URL) async throws -> FileTreeNode {
        let resourceValues = try rootURL.resourceValues(forKeys: Self.resourceKeys)

        guard resourceValues.isDirectory == true else {
            throw FileTreeLoadingError.rootIsNotDirectory(rootURL)
        }

        let children = try await loadChildren(of: rootURL)

        return makeNode(
            for: rootURL,
            resourceValues: resourceValues,
            childrenState: .loaded(children)
        )
    }

    func loadChildren(of directoryURL: URL) async throws -> [FileTreeNode] {
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        )

        return try childURLs
            .map { childURL in
                let resourceValues = try childURL.resourceValues(forKeys: Self.resourceKeys)
                return makeNode(for: childURL, resourceValues: resourceValues)
            }
            .sorted(by: Self.sortNodes)
    }

    private func makeNode(
        for url: URL,
        resourceValues: URLResourceValues,
        childrenState: FileTreeChildrenState? = nil
    ) -> FileTreeNode {
        let kind: FileTreeNodeKind = resourceValues.isDirectory == true ? .directory : .file
        let resolvedChildrenState = childrenState ?? defaultChildrenState(for: kind)

        return FileTreeNode(
            id: UUID(),
            url: url,
            name: displayName(for: url),
            kind: kind,
            isDocumentCandidate: isDocumentCandidate(url: url, kind: kind),
            childrenState: resolvedChildrenState,
            gitStatus: nil
        )
    }

    private func defaultChildrenState(for kind: FileTreeNodeKind) -> FileTreeChildrenState {
        switch kind {
        case .directory:
            return .notLoaded
        case .file:
            return .loaded([])
        }
    }

    private func displayName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    private func isDocumentCandidate(url: URL, kind: FileTreeNodeKind) -> Bool {
        guard kind == .file else {
            return false
        }

        return Self.documentExtensions.contains(url.pathExtension.lowercased())
    }

    private static func sortNodes(_ lhs: FileTreeNode, _ rhs: FileTreeNode) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind == .directory
        }

        let nameComparison = lhs.name.localizedStandardCompare(rhs.name)

        if nameComparison == .orderedSame {
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }

        return nameComparison == .orderedAscending
    }
}
