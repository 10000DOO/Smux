import Foundation

@MainActor
final class WorkspaceSessionPanelAttacher {
    var workspaceStore: WorkspaceStore?
    var panelStore: PanelStore?
    var workspaceSessionStore: WorkspaceSessionStore?

    init(
        workspaceStore: WorkspaceStore? = nil,
        panelStore: PanelStore? = nil,
        workspaceSessionStore: WorkspaceSessionStore? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.workspaceSessionStore = workspaceSessionStore
    }

    func replacePanel(
        with surface: PanelSurfaceDescriptor,
        preferredPanelID panelID: PanelNode.ID?
    ) {
        if let panelID, panelStore?.rootNode.containsLeaf(panelID: panelID) == true {
            panelStore?.replacePanel(panelID: panelID, with: surface)
            return
        }

        panelStore?.replaceFocusedPanel(with: surface)
    }

    func createPanel(
        splitDirection: SplitDirection,
        surface: PanelSurfaceDescriptor
    ) {
        panelStore?.createPanel(splitDirection: splitDirection, surface: surface)
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

    private func activeWorkspaceSession(for sessionID: WorkspaceSession.ID) -> WorkspaceSession? {
        guard let session = workspaceSessionStore?.session(for: sessionID),
              let activeWorkspaceID = workspaceStore?.activeWorkspace?.id,
              session.workspaceID == activeWorkspaceID else {
            return nil
        }

        return session
    }
}
