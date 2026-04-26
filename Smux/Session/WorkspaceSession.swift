import Foundation

nonisolated enum WorkspaceSessionKind: String, Codable, Hashable {
    case terminal
    case editor
    case preview
}

nonisolated enum WorkspaceSessionContentReference: Codable, Hashable {
    case terminal(TerminalSession.ID)
    case editor(DocumentSession.ID)
    case preview(previewID: PreviewState.ID, sourceDocumentID: DocumentSession.ID)
}

nonisolated struct WorkspaceSession: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var kind: WorkspaceSessionKind
    var content: WorkspaceSessionContentReference
    var title: String
    var createdAt: Date
    var lastActiveAt: Date

    init(
        id: ID = ID(),
        workspaceID: Workspace.ID,
        kind: WorkspaceSessionKind,
        content: WorkspaceSessionContentReference,
        title: String,
        createdAt: Date,
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.content = content
        self.title = title
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt ?? createdAt
    }
}

extension WorkspaceSession {
    nonisolated var terminalID: TerminalSession.ID? {
        guard case .terminal(let terminalID) = content else {
            return nil
        }

        return terminalID
    }

    nonisolated var documentID: DocumentSession.ID? {
        switch content {
        case .editor(let documentID):
            return documentID
        case .preview(_, let sourceDocumentID):
            return sourceDocumentID
        case .terminal:
            return nil
        }
    }

    nonisolated var previewID: PreviewState.ID? {
        guard case .preview(let previewID, _) = content else {
            return nil
        }

        return previewID
    }
}

extension WorkspaceSession {
    nonisolated init(terminal: TerminalSession, id: ID = ID()) {
        self.init(
            id: id,
            workspaceID: terminal.workspaceID,
            kind: .terminal,
            content: .terminal(terminal.id),
            title: terminal.title,
            createdAt: terminal.createdAt,
            lastActiveAt: terminal.lastActivityAt
        )
    }

    nonisolated init(document: DocumentSession, id: ID = ID(), createdAt: Date = Date()) {
        self.init(
            id: id,
            workspaceID: document.workspaceID,
            kind: .editor,
            content: .editor(document.id),
            title: document.url.lastPathComponent,
            createdAt: createdAt,
            lastActiveAt: createdAt
        )
    }

    nonisolated init(preview: PreviewState, workspaceID: Workspace.ID, id: ID = ID(), createdAt: Date = Date()) {
        self.init(
            id: id,
            workspaceID: workspaceID,
            kind: .preview,
            content: .preview(previewID: preview.id, sourceDocumentID: preview.sourceDocumentID),
            title: "Preview",
            createdAt: createdAt,
            lastActiveAt: createdAt
        )
    }
}

extension WorkspaceSessionContentReference {
    nonisolated var kind: WorkspaceSessionKind {
        switch self {
        case .terminal:
            return .terminal
        case .editor:
            return .editor
        case .preview:
            return .preview
        }
    }
}
