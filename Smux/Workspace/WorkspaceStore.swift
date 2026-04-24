import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var activeWorkspace: Workspace?
    @Published var workspaces: [Workspace] = []
    @Published var isOpeningWorkspace = false
    @Published var openErrorMessage: String?

    func selectWorkspace(id: Workspace.ID) {}

    func closeWorkspace(id: Workspace.ID) {}
}
