import Foundation

enum DocumentOpenMode: String, Codable, Hashable {
    case editor
    case preview
    case split
}

@MainActor
protocol WorkspaceOpening {
    func openWorkspace(rootURL: URL) async throws
    func closeWorkspace(id: Workspace.ID) async
}

@MainActor
protocol DocumentOpening {
    func openDocument(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        replacingPanel panelID: PanelNode.ID?
    ) async throws

    func openDocumentInNewPanel(
        _ url: URL,
        preferredSurface: DocumentOpenMode,
        splitDirection: SplitDirection
    ) async throws
}

extension DocumentOpening {
    func openDocument(_ url: URL, preferredSurface: DocumentOpenMode) async throws {
        try await openDocument(url, preferredSurface: preferredSurface, replacingPanel: nil)
    }
}

@MainActor
protocol TerminalCommanding {
    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID?) async throws
}

extension TerminalCommanding {
    func createTerminal(in workspaceID: Workspace.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: nil)
    }

    func createTerminal(in workspaceID: Workspace.ID, replacingPanel panelID: PanelNode.ID) async throws {
        try await createTerminal(in: workspaceID, replacingPanel: Optional(panelID))
    }
}

@MainActor
protocol PanelCommanding {
    func focus(panelID: PanelNode.ID?)
    func createPanel(splitDirection: SplitDirection, surface: PanelSurfaceDescriptor)
    func splitPanel(panelID: PanelNode.ID, direction: SplitDirection, surface: PanelSurfaceDescriptor)
    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor)
    func updateSplitRatio(splitID: PanelNode.ID, ratio: Double)
    func focusNextPanel()
    func focusPreviousPanel()
    func closeFocusedPanel()
}

extension WorkspaceCoordinator {
    func focus(panelID: PanelNode.ID?) {
        panelStore?.focus(panelID: panelID)
    }

    func createPanel(splitDirection: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelStore?.createPanel(splitDirection: splitDirection, surface: surface)
    }

    func splitPanel(panelID: PanelNode.ID, direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        panelStore?.splitPanel(panelID: panelID, direction: direction, surface: surface)
    }

    func updateSplitRatio(splitID: PanelNode.ID, ratio: Double) {
        panelStore?.updateSplitRatio(splitID: splitID, ratio: ratio)
    }

    func focusNextPanel() {
        panelStore?.focusNextPanel()
    }

    func focusPreviousPanel() {
        panelStore?.focusPreviousPanel()
    }

    func closeFocusedPanel() {
        guard let panelStore, panelStore.canCloseFocusedPanel else {
            return
        }

        let surface = panelStore.focusedSurface
        panelStore.closeFocusedPanel()
        cleanupDetachedPanelSurface(surface)
    }

    func cleanupDetachedPanelSurface(_ surface: PanelSurfaceDescriptor?) {
        guard let surface else {
            return
        }

        switch surface {
        case .session(let sessionID):
            cleanupDetachedWorkspaceSession(id: sessionID)
        case .empty:
            break
        }
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
            // Document content may be shared by preview sessions and text buffers.
            workspaceSessionStore?.removeSession(id: session.id)
        }
    }
}
