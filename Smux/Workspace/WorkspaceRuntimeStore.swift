import Combine
import Foundation

nonisolated struct WorkspaceRuntimeState: Equatable {
    var workspaceID: Workspace.ID
    var panelTree: PanelNode
    var focusedPanelID: PanelNode.ID?
}

@MainActor
final class WorkspaceRuntimeStore: ObservableObject {
    @Published private(set) var states: [Workspace.ID: WorkspaceRuntimeState]

    init(states: [Workspace.ID: WorkspaceRuntimeState] = [:]) {
        self.states = states
    }

    func state(for workspaceID: Workspace.ID) -> WorkspaceRuntimeState? {
        states[workspaceID]
    }

    func park(
        workspaceID: Workspace.ID,
        panelTree: PanelNode,
        focusedPanelID: PanelNode.ID?
    ) {
        states[workspaceID] = WorkspaceRuntimeState(
            workspaceID: workspaceID,
            panelTree: panelTree,
            focusedPanelID: focusedPanelID
        )
    }

    func moveState(from sourceWorkspaceID: Workspace.ID, to targetWorkspaceID: Workspace.ID) -> WorkspaceRuntimeState? {
        guard sourceWorkspaceID != targetWorkspaceID else {
            return states[targetWorkspaceID]
        }

        guard var state = states.removeValue(forKey: sourceWorkspaceID) else {
            return nil
        }

        state.workspaceID = targetWorkspaceID
        states[targetWorkspaceID] = state
        return state
    }

    func removeState(for workspaceID: Workspace.ID) {
        states.removeValue(forKey: workspaceID)
    }
}
