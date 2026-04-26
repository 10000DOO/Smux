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

nonisolated struct DocumentSaveFailure: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case sessionNotFound
        case missingSession
        case saveAlreadyInProgress
        case conflicted
        case fileIO
    }

    var kind: Kind
    var message: String
}

nonisolated struct DocumentSaveResult: Hashable, Sendable {
    var documentID: DocumentSession.ID?
    var state: DocumentSaveState
    var conflict: DocumentConflict?
    var failure: DocumentSaveFailure?

    static func saved(documentID: DocumentSession.ID) -> DocumentSaveResult {
        DocumentSaveResult(
            documentID: documentID,
            state: .clean,
            conflict: nil,
            failure: nil
        )
    }

    static func dirty(documentID: DocumentSession.ID) -> DocumentSaveResult {
        DocumentSaveResult(
            documentID: documentID,
            state: .dirty,
            conflict: nil,
            failure: nil
        )
    }

    static func conflicted(
        documentID: DocumentSession.ID,
        conflict: DocumentConflict
    ) -> DocumentSaveResult {
        DocumentSaveResult(
            documentID: documentID,
            state: .conflicted,
            conflict: conflict,
            failure: nil
        )
    }

    static func failed(
        documentID: DocumentSession.ID?,
        failure: DocumentSaveFailure
    ) -> DocumentSaveResult {
        DocumentSaveResult(
            documentID: documentID,
            state: .failed,
            conflict: nil,
            failure: failure
        )
    }
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
