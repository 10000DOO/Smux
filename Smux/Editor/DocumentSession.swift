import Foundation

enum DocumentLanguage: String, Codable, Hashable {
    case markdown
    case mermaid
    case plainText
}

enum DocumentSaveState: String, Codable, Hashable {
    case clean
    case dirty
    case saving
    case failed
    case conflicted
}

struct FileFingerprint: Codable, Hashable {
    var modificationDate: Date?
    var size: Int64?
    var contentHash: String?
}

struct DocumentConflict: Codable, Hashable {
    var detectedAt: Date
    var loadedFingerprint: FileFingerprint?
    var currentFingerprint: FileFingerprint?
}

struct DocumentSession: Identifiable, Codable, Hashable {
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
