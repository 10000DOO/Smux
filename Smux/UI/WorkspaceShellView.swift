import SwiftUI

struct WorkspaceShellView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var panelStore: PanelStore
    @ObservedObject var notificationStore: NotificationStore

    var body: some View {
        HStack(spacing: 0) {
            LeftRailView(
                workspace: workspaceStore.activeWorkspace,
                notifications: notificationStore.notifications
            )

            Divider()

            SplitPanelView(node: panelStore.rootNode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
