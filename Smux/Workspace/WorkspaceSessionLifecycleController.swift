import Foundation

nonisolated enum WorkspaceSessionCreateKind: Equatable {
    case terminal
}

nonisolated struct WorkspaceSessionCreateRequest: Equatable {
    var workspaceID: Workspace.ID
    var kind: WorkspaceSessionCreateKind
}

nonisolated struct WorkspaceSessionAttachmentRequest: Equatable {
    var replacingPanelID: PanelNode.ID?

    static func automatic(replacingPanelID: PanelNode.ID? = nil) -> WorkspaceSessionAttachmentRequest {
        WorkspaceSessionAttachmentRequest(replacingPanelID: replacingPanelID)
    }
}

@MainActor
final class WorkspaceSessionLifecycleController {
    var workspaceStore: WorkspaceStore?
    var panelAttacher: WorkspaceSessionPanelAttacher
    var sessionCreator: WorkspaceSessionCreator
    var terminalSessionController: TerminalSessionController?
    var previewSessionStore: PreviewSessionStore?
    var workspaceSessionStore: WorkspaceSessionStore?

    init(
        workspaceStore: WorkspaceStore? = nil,
        panelAttacher: WorkspaceSessionPanelAttacher,
        sessionCreator: WorkspaceSessionCreator,
        terminalSessionController: TerminalSessionController? = nil,
        previewSessionStore: PreviewSessionStore? = nil,
        workspaceSessionStore: WorkspaceSessionStore? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.panelAttacher = panelAttacher
        self.sessionCreator = sessionCreator
        self.terminalSessionController = terminalSessionController
        self.previewSessionStore = previewSessionStore
        self.workspaceSessionStore = workspaceSessionStore
    }

    func createSession(
        _ request: WorkspaceSessionCreateRequest,
        attachment: WorkspaceSessionAttachmentRequest?
    ) async throws -> WorkspaceSession {
        switch request.kind {
        case .terminal:
            let session = try await createTerminalSession(in: request.workspaceID)
            if let attachment {
                panelAttacher.showSession(id: session.id, replacingPanel: attachment.replacingPanelID)
            }
            return session
        }
    }

    func openDocument(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        replacingPanel panelID: PanelNode.ID?
    ) async throws {
        let workspace = try activeWorkspace()
        let editorSession = sessionCreator.createDocumentSession(in: workspace, url: url)

        switch preferredSurface {
        case .editor:
            panelAttacher.replacePanel(with: .session(sessionID: editorSession.session.id), preferredPanelID: panelID)
        case .preview:
            let previewSession = await sessionCreator.createPreviewSession(
                in: workspace,
                sourceDocumentID: editorSession.documentID
            )
            panelAttacher.replacePanel(with: .session(sessionID: previewSession.id), preferredPanelID: panelID)
        case .split:
            panelAttacher.replacePanel(with: .session(sessionID: editorSession.session.id), preferredPanelID: panelID)
            let previewSession = await sessionCreator.createPreviewSession(
                in: workspace,
                sourceDocumentID: editorSession.documentID
            )
            panelAttacher.panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: .session(sessionID: previewSession.id)
            )
        }
    }

    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws {
        let workspace = try activeWorkspace()
        let editorSession = sessionCreator.createDocumentSession(in: workspace, url: url)

        switch preferredSurface {
        case .editor:
            panelAttacher.createPanel(splitDirection: splitDirection, surface: .session(sessionID: editorSession.session.id))
        case .preview:
            let previewSession = await sessionCreator.createPreviewSession(
                in: workspace,
                sourceDocumentID: editorSession.documentID
            )
            panelAttacher.createPanel(splitDirection: splitDirection, surface: .session(sessionID: previewSession.id))
        case .split:
            panelAttacher.createPanel(splitDirection: splitDirection, surface: .session(sessionID: editorSession.session.id))
            let previewSession = await sessionCreator.createPreviewSession(
                in: workspace,
                sourceDocumentID: editorSession.documentID
            )
            panelAttacher.panelStore?.splitFocusedPanel(
                direction: .horizontal,
                surface: .session(sessionID: previewSession.id)
            )
        }
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID?) async throws {
        let session = try await createTerminalSession(in: workspaceID)
        panelAttacher.replacePanel(with: .session(sessionID: session.id), preferredPanelID: panelID)
    }

    func focusSession(id sessionID: WorkspaceSession.ID) {
        panelAttacher.focusSession(id: sessionID)
    }

    func showSession(id sessionID: WorkspaceSession.ID, replacingPanel panelID: PanelNode.ID?) {
        panelAttacher.showSession(id: sessionID, replacingPanel: panelID)
    }

    func closeSession(id sessionID: WorkspaceSession.ID) {
        guard activeWorkspaceSession(for: sessionID) != nil else {
            return
        }

        while let panelStore = panelAttacher.panelStore,
              let panelID = panelStore.rootNode.panelID(containingWorkspaceSession: sessionID) {
            panelStore.replacePanel(panelID: panelID, with: .empty)
        }

        cleanupDetachedWorkspaceSession(id: sessionID)
    }

    private func createTerminalSession(in workspaceID: Workspace.ID) async throws -> WorkspaceSession {
        guard let workspace = workspaceStore?.workspaces.first(where: { $0.id == workspaceID }) else {
            throw WorkspaceCoordinatorError.workspaceNotFound
        }

        return try await sessionCreator.createTerminalSession(in: workspace)
    }

    private func activeWorkspace() throws -> Workspace {
        guard let workspace = workspaceStore?.activeWorkspace else {
            throw WorkspaceCoordinatorError.missingActiveWorkspace
        }

        return workspace
    }

    private func cleanupDetachedWorkspaceSession(id sessionID: WorkspaceSession.ID) {
        guard let session = workspaceSessionStore?.session(for: sessionID) else {
            return
        }

        switch session.content {
        case .terminal(let terminalID):
            terminalSessionController?.removeSession(sessionID: terminalID)
            workspaceSessionStore?.removeSession(id: session.id)
        case .preview(let previewID, _):
            previewSessionStore?.removePreview(previewID: previewID)
            workspaceSessionStore?.removeSession(id: session.id)
        case .editor:
            workspaceSessionStore?.removeSession(id: session.id)
        }
    }

    private func activeWorkspaceSession(for sessionID: WorkspaceSession.ID) -> WorkspaceSession? {
        guard let session = workspaceSessionStore?.session(for: sessionID),
              let activeWorkspaceID = workspaceStore?.activeWorkspace?.id,
              session.workspaceID == activeWorkspaceID else {
            return nil
        }

        return session
    }
}
