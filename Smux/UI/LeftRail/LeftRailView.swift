import SwiftUI

struct LeftRailView: View {
    var workspace: Workspace?
    var workspaces: [Workspace] = []
    var recentWorkspaces: [RecentWorkspace] = []
    var sessionItems: [LeftRailSessionPresentation] = []
    var notificationSummary: LeftRailNotificationSummary = .empty
    var visibleNotifications: [WorkspaceNotification] = []
    var fileTreeRoot: FileTreeNode? = nil
    var selectedFileTreeNodeID: FileTreeNode.ID? = nil
    var isCollapsed = false
    var onExpandFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onSelectFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onCreateSession: () -> Void = {}
    var onSelectSession: (WorkspaceLayoutSession.ID) -> Void = { _ in }
    var onCloseSession: (WorkspaceLayoutSession.ID) -> Void = { _ in }
    var onOpenWorkspace: () -> Void = {}
    var onToggleCollapsed: () -> Void = {}
    var onSelectWorkspace: (Workspace.ID) -> Void = { _ in }
    var onCloseWorkspace: (Workspace.ID) -> Void = { _ in }
    var onOpenRecentWorkspace: (RecentWorkspace) -> Void = { _ in }
    var onSelectNotification: (WorkspaceNotification.ID) -> Void = { _ in }
    var onAcknowledgeNotification: (WorkspaceNotification.ID) -> Void = { _ in }

    var body: some View {
        Group {
            if isCollapsed {
                LeftRailCollapsedView(
                    sessionItems: sessionItems,
                    notificationSummary: notificationSummary,
                    visibleNotifications: visibleNotifications,
                    onToggleCollapsed: onToggleCollapsed,
                    onOpenWorkspace: onOpenWorkspace,
                    onCreateSession: onCreateSession,
                    onSelectSession: onSelectSession,
                    onSelectNotification: onSelectNotification
                )
            } else {
                expandedBody
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 1)
        }
    }
}

private extension LeftRailView {
    var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            LeftRailHeaderView(
                workspace: workspace,
                onToggleCollapsed: onToggleCollapsed,
                onOpenWorkspace: onOpenWorkspace
            )

            ScrollView {
                VStack(alignment: .leading, spacing: LeftRailLayoutMetrics.sectionSpacing) {
                    LeftRailWorkspaceListView(
                        activeWorkspace: workspace,
                        workspaces: workspaces,
                        recentWorkspaces: recentWorkspaces,
                        onSelectWorkspace: onSelectWorkspace,
                        onCloseWorkspace: onCloseWorkspace,
                        onOpenRecentWorkspace: onOpenRecentWorkspace
                    )

                    LeftRailSessionListView(
                        sessionItems: sessionItems,
                        onCreateSession: onCreateSession,
                        onSelectSession: onSelectSession,
                        onCloseSession: onCloseSession
                    )

                    fileTreeSection

                    LeftRailActivityView(
                        notificationSummary: notificationSummary,
                        visibleNotifications: visibleNotifications,
                        onSelectNotification: onSelectNotification,
                        onAcknowledgeNotification: onAcknowledgeNotification
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
    }

    var fileTreeSection: some View {
        LeftRailSectionView(title: "Files") {
            if let fileTreeRoot {
                LeftRailFileTreeView(
                    rootNode: fileTreeRoot,
                    selectedNodeID: selectedFileTreeNodeID,
                    onExpand: onExpandFileTreeNode,
                    onSelect: onSelectFileTreeNode
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(workspace?.rootURL.lastPathComponent ?? "Workspace", systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Label("File tree pending", systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}
