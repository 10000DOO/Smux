import Foundation

nonisolated enum DocumentLanguage: String, Codable, Hashable {
    case markdown
    case mermaid
    case plainText
}

nonisolated enum DocumentSaveState: String, Codable, Hashable {
    case clean
    case dirty
    case saving
    case failed
    case conflicted
}

nonisolated struct FileFingerprint: Codable, Hashable {
    var modificationDate: Date?
    var size: Int64?
    var contentHash: String?
}

nonisolated struct DocumentConflict: Codable, Hashable {
    var detectedAt: Date
    var loadedFingerprint: FileFingerprint?
    var currentFingerprint: FileFingerprint?
}

nonisolated struct DocumentSession: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var url: URL
    var language: DocumentLanguage
    var textVersion: Int
    var fileFingerprint: FileFingerprint?
    var isDirty: Bool
    var saveState: DocumentSaveState
    var conflict: DocumentConflict?
}
