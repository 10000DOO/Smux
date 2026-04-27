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
protocol WorkspaceSessionCommanding {
    func focusSession(id: WorkspaceSession.ID)
    func showSession(id: WorkspaceSession.ID, replacingPanel panelID: PanelNode.ID?)
    func closeSession(id: WorkspaceSession.ID)
}

extension WorkspaceSessionCommanding {
    func showSession(id: WorkspaceSession.ID) {
        showSession(id: id, replacingPanel: nil)
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

        panelStore.closeFocusedPanel()
    }

    func focusSession(id sessionID: WorkspaceSession.ID) {
        guard activeWorkspaceSession(for: sessionID) != nil,
              let panelID = panelStore?.rootNode.panelID(containingWorkspaceSession: sessionID) else {
            return
        }

        panelStore?.focus(panelID: panelID)
    }

    func showSession(id sessionID: WorkspaceSession.ID, replacingPanel panelID: PanelNode.ID?) {
        guard activeWorkspaceSession(for: sessionID) != nil else {
            return
        }

        if let visiblePanelID = panelStore?.rootNode.panelID(containingWorkspaceSession: sessionID) {
            panelStore?.focus(panelID: visiblePanelID)
            return
        }

        let surface = PanelSurfaceDescriptor.session(sessionID: sessionID)

        if let panelID,
           panelStore?.rootNode.containsLeaf(panelID: panelID) == true,
           panelStore?.rootNode.surface(forLeaf: panelID) == .empty {
            panelStore?.replacePanel(panelID: panelID, with: surface)
            return
        }

        if panelStore?.focusedSurface == .empty {
            panelStore?.replaceFocusedPanel(with: surface)
            return
        }

        panelStore?.createPanel(splitDirection: .horizontal, surface: surface)
    }

    func closeSession(id sessionID: WorkspaceSession.ID) {
        guard activeWorkspaceSession(for: sessionID) != nil else {
            return
        }

        while let panelStore,
              let panelID = panelStore.rootNode.panelID(containingWorkspaceSession: sessionID) {
            panelStore.replacePanel(panelID: panelID, with: .empty)
        }

        cleanupDetachedWorkspaceSession(id: sessionID)
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

    private func activeWorkspaceSession(for sessionID: WorkspaceSession.ID) -> WorkspaceSession? {
        guard let session = workspaceSessionStore?.session(for: sessionID),
              let activeWorkspaceID = workspaceStore?.activeWorkspace?.id,
              session.workspaceID == activeWorkspaceID else {
            return nil
        }

        return session
    }
}
