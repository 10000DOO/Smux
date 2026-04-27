import Foundation

@MainActor
final class WorkspaceSessionCreator {
    var documentSessionStore: DocumentSessionStore?
    var terminalSessionController: TerminalSessionController?
    var previewSessionStore: PreviewSessionStore?
    var workspaceSessionStore: WorkspaceSessionStore?
    var previewRenderCoordinator: PreviewRenderingCoordinating?

    init(
        documentSessionStore: DocumentSessionStore? = nil,
        terminalSessionController: TerminalSessionController? = nil,
        previewSessionStore: PreviewSessionStore? = nil,
        workspaceSessionStore: WorkspaceSessionStore? = nil,
        previewRenderCoordinator: PreviewRenderingCoordinating? = nil
    ) {
        self.documentSessionStore = documentSessionStore
        self.terminalSessionController = terminalSessionController
        self.previewSessionStore = previewSessionStore
        self.workspaceSessionStore = workspaceSessionStore
        self.previewRenderCoordinator = previewRenderCoordinator
    }

    func createTerminalSession(
        in workspace: Workspace,
        command: [String] = []
    ) async throws -> WorkspaceSession {
        guard let session = try await terminalSessionController?.createSession(in: workspace, command: command) else {
            let missingSession = WorkspaceSession(
                workspaceID: workspace.id,
                kind: .terminal,
                content: .terminal(TerminalSession.ID()),
                title: "Terminal",
                createdAt: Date()
            )
            workspaceSessionStore?.upsertSession(missingSession)
            return missingSession
        }

        let workspaceSession = WorkspaceSession(terminal: session)
        workspaceSessionStore?.upsertSession(workspaceSession)
        return workspaceSession
    }

    func createDocumentSession(
        in workspace: Workspace,
        url: URL
    ) -> (session: WorkspaceSession, documentID: DocumentSession.ID) {
        let documentID = DocumentSession.ID()
        let documentSession = DocumentSession.make(
            id: documentID,
            workspaceID: workspace.id,
            url: url
        )
        documentSessionStore?.upsertSession(documentSession)

        let workspaceSession = WorkspaceSession(document: documentSession)
        workspaceSessionStore?.upsertSession(workspaceSession)
        return (workspaceSession, documentID)
    }

    func createPreviewSession(
        in workspace: Workspace,
        sourceDocumentID documentID: DocumentSession.ID
    ) async -> WorkspaceSession {
        let previewID = PreviewState.ID()
        previewSessionStore?.bind(previewID: previewID, sourceDocumentID: documentID)

        let workspaceSession = WorkspaceSession(
            id: WorkspaceSession.ID(),
            workspaceID: workspace.id,
            kind: .preview,
            content: .preview(previewID: previewID, sourceDocumentID: documentID),
            title: "Preview",
            createdAt: Date()
        )
        workspaceSessionStore?.upsertSession(workspaceSession)
        await previewRenderCoordinator?.render(previewID: previewID)
        return workspaceSession
    }
}
