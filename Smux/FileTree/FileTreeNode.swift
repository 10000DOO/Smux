import Foundation

nonisolated enum FileTreeNodeKind: String, Codable, Hashable {
    case file
    case directory
}

nonisolated enum GitFileStatus: String, Codable, Hashable {
    case unmodified
    case modified
    case added
    case deleted
    case untracked
    case ignored
    case unknown
}

nonisolated indirect enum FileTreeChildrenState: Codable, Hashable {
    case notLoaded
    case loading
    case loaded([FileTreeNode])
    case failed(message: String)
}

nonisolated struct FileTreeNode: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var url: URL
    var name: String
    var kind: FileTreeNodeKind
    var isDocumentCandidate: Bool
    var childrenState: FileTreeChildrenState
    var gitStatus: GitFileStatus?
}
