import SwiftUI

struct WorkspaceShellView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var panelStore: PanelStore
    @ObservedObject var notificationStore: NotificationStore

    var body: some View {
        HStack(spacing: 0) {
            LeftRailView(
                workspace: workspaceStore.activeWorkspace,
                rootNode: panelStore.rootNode,
                focusedPanelID: panelStore.focusedPanelID,
                notifications: notificationStore.notifications
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
    }
}
