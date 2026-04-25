import SwiftUI

struct WorkspaceShellView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var panelStore: PanelStore
    @ObservedObject var notificationStore: NotificationStore
    @ObservedObject var fileTreeStore: FileTreeStore
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @ObservedObject var terminalSessionController: TerminalSessionController
    @ObservedObject var terminalOutputStore: TerminalOutputStore
    var commandRouter: AppCommandRouter

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
                documentSessionStore: documentSessionStore,
                previewSessionStore: previewSessionStore,
                documentTextStore: documentTextStore,
                terminalSessionController: terminalSessionController,
                terminalOutputStore: terminalOutputStore,
                onFocus: { panelStore.focus(panelID: $0) },
                onReplaceSurface: { panelID, surface in
                    panelStore.replacePanel(panelID: panelID, with: surface)
                },
                onSplit: { panelID, direction in
                    panelStore.splitPanel(panelID: panelID, direction: direction, surface: .empty)
                },
                onCreateTerminal: createTerminal
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

        guard let node = fileTreeStore.root?.node(id: nodeID) else {
            return
        }

        switch node.kind {
        case .directory:
            expandFileTreeNode(nodeID)
        case .file:
            Task { @MainActor in
                do {
                    try await commandRouter.openDocument(node.url, preferredSurface: .split)
                } catch {
                    workspaceStore.openErrorMessage = "Failed to open document: \(error.localizedDescription)"
                }
            }
        }
    }

    func createTerminal() {
        guard let workspaceID = workspaceStore.activeWorkspace?.id else {
            workspaceStore.openErrorMessage = "No workspace is currently active."
            return
        }

        Task { @MainActor in
            do {
                try await commandRouter.createTerminal(in: workspaceID)
            } catch {
                workspaceStore.openErrorMessage = "Failed to create terminal: \(error.localizedDescription)"
            }
        }
    }
}

private extension FileTreeNode {
    func node(id targetID: ID) -> FileTreeNode? {
        if id == targetID {
            return self
        }

        guard case .loaded(let children) = childrenState else {
            return nil
        }

        for child in children {
            if let matchingNode = child.node(id: targetID) {
                return matchingNode
            }
        }

        return nil
    }
}
