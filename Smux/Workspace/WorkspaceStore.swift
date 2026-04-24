import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var activeWorkspace: Workspace?
    @Published var workspaces: [Workspace] = []
    @Published var isOpeningWorkspace = false
    @Published var openErrorMessage: String?

    init(activeWorkspace: Workspace? = nil, workspaces: [Workspace] = []) {
        self.activeWorkspace = activeWorkspace
        self.workspaces = workspaces

        if let activeWorkspace, !workspaces.contains(where: { $0.id == activeWorkspace.id }) {
            self.workspaces.append(activeWorkspace)
        }

        if self.activeWorkspace == nil {
            self.activeWorkspace = self.workspaces.first
        }
    }

    func setActiveWorkspace(_ workspace: Workspace) {
        let activeWorkspace = workspace.markingActive()
        upsertWorkspace(activeWorkspace)
        self.activeWorkspace = activeWorkspace
    }

    func upsertWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
    }

    func selectWorkspace(id: Workspace.ID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }

        setActiveWorkspace(workspace)
    }

    func closeWorkspace(id: Workspace.ID) {
        workspaces.removeAll { $0.id == id }

        guard activeWorkspace?.id == id else {
            return
        }

        activeWorkspace = workspaces.first
    }

    func clearOpenError() {
        openErrorMessage = nil
    }
}
