import SwiftUI

struct WorkspaceShellView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var panelStore: PanelStore
    @ObservedObject var notificationStore: NotificationStore
    @ObservedObject var fileTreeStore: FileTreeStore

    var body: some View {
        HStack(spacing: 0) {
            LeftRailView(
                workspace: workspaceStore.activeWorkspace,
                rootNode: panelStore.rootNode,
                focusedPanelID: panelStore.focusedPanelID,
                notifications: notificationStore.notifications,
                fileTreeRoot: fileTreeStore.root,
                selectedFileTreeNodeID: fileTreeStore.selectedNodeID,
                onExpandFileTreeNode: expandFileTreeNode,
                onSelectFileTreeNode: selectFileTreeNode
            )

            Divider()

            SplitPanelView(
                node: panelStore.rootNode,
                focusedPanelID: panelStore.focusedPanelID,
                onFocus: { panelStore.focus(panelID: $0) },
                onReplaceSurface: { panelID, surface in
                    panelStore.replacePanel(panelID: panelID, with: surface)
                },
                onSplit: { panelID, direction in
                    panelStore.splitPanel(panelID: panelID, direction: direction, surface: .empty)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .task(id: workspaceStore.activeWorkspace?.id) {
            await loadFileTreeForActiveWorkspace()
        }
    }
}

private extension WorkspaceShellView {
    func loadFileTreeForActiveWorkspace() async {
        guard let workspace = workspaceStore.activeWorkspace else {
            fileTreeStore.clear()
            return
        }

        do {
            try await fileTreeStore.loadRoot(workspace: workspace)
        } catch is CancellationError {
            return
        } catch {
            workspaceStore.openErrorMessage = "Failed to load file tree: \(error.localizedDescription)"
        }
    }

    func expandFileTreeNode(_ nodeID: FileTreeNode.ID) {
        Task { @MainActor in
            do {
                try await fileTreeStore.expand(nodeID: nodeID)
            } catch {
                workspaceStore.openErrorMessage = "Failed to expand folder: \(error.localizedDescription)"
            }
        }
    }

    func selectFileTreeNode(_ nodeID: FileTreeNode.ID) {
        fileTreeStore.selectedNodeID = nodeID
    }
}
