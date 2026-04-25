import Foundation

nonisolated enum DocumentLanguage: String, Codable, Hashable, Sendable {
    case markdown
    case mermaid
    case plainText
}

extension DocumentLanguage {
    static func detect(for url: URL) -> DocumentLanguage {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "mmd", "mermaid":
            return .mermaid
        default:
            return .plainText
        }
    }
}

nonisolated enum DocumentSaveState: String, Codable, Hashable, Sendable {
    case clean
    case dirty
    case saving
    case failed
    case conflicted
}

nonisolated struct FileFingerprint: Codable, Hashable, Sendable {
    var modificationDate: Date?
    var size: Int64?
    var contentHash: String?
}

nonisolated struct DocumentConflict: Codable, Hashable, Sendable {
    var detectedAt: Date
    var loadedFingerprint: FileFingerprint?
    var currentFingerprint: FileFingerprint?
}

nonisolated struct DocumentSession: Identifiable, Codable, Hashable, Sendable {
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

extension DocumentSession {
    static func make(
        id: ID = UUID(),
        workspaceID: Workspace.ID,
        url: URL,
        language: DocumentLanguage? = nil,
        textVersion: Int = 0,
        fileFingerprint: FileFingerprint? = nil,
        isDirty: Bool = false,
        saveState: DocumentSaveState = .clean,
        conflict: DocumentConflict? = nil
    ) -> DocumentSession {
        DocumentSession(
            id: id,
            workspaceID: workspaceID,
            url: url,
            language: language ?? DocumentLanguage.detect(for: url),
            textVersion: textVersion,
            fileFingerprint: fileFingerprint,
            isDirty: isDirty,
            saveState: saveState,
            conflict: conflict
        )
    }
}
