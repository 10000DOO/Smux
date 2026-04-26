import SwiftUI

struct LeftRailView: View {
    var workspace: Workspace?
    var workspaces: [Workspace] = []
    var recentWorkspaces: [RecentWorkspace] = []
    var rootNode: PanelNode
    var focusedPanelID: PanelNode.ID?
    var notifications: [WorkspaceNotification]
    var fileTreeRoot: FileTreeNode? = nil
    var selectedFileTreeNodeID: FileTreeNode.ID? = nil
    var onExpandFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onSelectFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onSelectWorkspace: (Workspace.ID) -> Void = { _ in }
    var onCloseWorkspace: (Workspace.ID) -> Void = { _ in }
    var onOpenRecentWorkspace: (RecentWorkspace) -> Void = { _ in }
    var onSelectNotification: (WorkspaceNotification.ID) -> Void = { _ in }
    var onAcknowledgeNotification: (WorkspaceNotification.ID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceSummary

            Divider()

            workspaceList

            Divider()

            panelsSummary

            Divider()

            fileTreeSection

            Spacer()

            latestNotifications
        }
        .padding(14)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension LeftRailView {
    var workspaceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Workspace", systemImage: "macwindow")
                .font(.subheadline)
            Text(workspace?.displayName ?? "No Workspace")
                .font(.headline)
                .lineLimit(1)
            Text(workspace?.rootURL.path ?? "Smux")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let gitBranch = workspace?.gitBranch {
                Label(gitBranch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    var workspaceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open", systemImage: "sidebar.left")
                .font(.subheadline)

            if workspaces.isEmpty {
                Text("No open workspaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workspaces) { listedWorkspace in
                    workspaceRow(listedWorkspace)
                }
            }

            if !recentWorkspaces.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(recentWorkspaces.prefix(3)) { recentWorkspace in
                    Button {
                        onOpenRecentWorkspace(recentWorkspace)
                    } label: {
                        Label(recentWorkspace.displayName, systemImage: "clock")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    func workspaceRow(_ listedWorkspace: Workspace) -> some View {
        HStack(spacing: 6) {
            Button {
                onSelectWorkspace(listedWorkspace.id)
            } label: {
                Label(
                    listedWorkspace.displayName,
                    systemImage: listedWorkspace.id == workspace?.id ? "smallcircle.filled.circle" : "circle"
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                onCloseWorkspace(listedWorkspace.id)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close workspace")
        }
        .font(.caption)
        .foregroundStyle(listedWorkspace.id == workspace?.id ? .primary : .secondary)
    }

    var panelsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Panels", systemImage: "rectangle.split.3x1")
                .font(.subheadline)
            Text("\(panelSummaries.count) open")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(panelSummaries.prefix(4)) { panel in
                let presentation = PanelSurfacePresentation(surface: panel.surface)

                HStack(spacing: 6) {
                    Image(systemName: presentation.systemImage)
                        .frame(width: 14)
                    Text(presentation.title)
                        .lineLimit(1)
                    if panel.isFocused {
                        Text("Focused")
                            .foregroundStyle(.primary)
                    }
                }
                .font(.caption)
                .foregroundStyle(panel.isFocused ? .primary : .secondary)
            }
        }
    }

    var fileTreeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Files", systemImage: "folder")
                .font(.subheadline)

            if let fileTreeRoot {
                LeftRailFileTreeView(
                    rootNode: fileTreeRoot,
                    selectedNodeID: selectedFileTreeNodeID,
                    onExpand: onExpandFileTreeNode,
                    onSelect: onSelectFileTreeNode
                )
            } else {
                fileTreePlaceholder
            }
        }
    }

    var fileTreePlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    var latestNotifications: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Latest", systemImage: "bell")
                    .font(.subheadline)
                if notificationSummary.totalCount > 0 {
                    Text("\(notificationSummary.totalCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            notificationStatusChips

            if visibleNotifications.isEmpty {
                Text("No notifications")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleNotifications) { notification in
                    notificationRow(notification)
                }
            }
        }
    }

    @ViewBuilder
    var notificationStatusChips: some View {
        if !notificationSummary.items.isEmpty {
            HStack(spacing: 6) {
                ForEach(notificationSummary.items) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                        Text("\(item.count)")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .help(item.title)
                }
            }
        } else {
            EmptyView()
        }
    }

    func notificationRow(_ notification: WorkspaceNotification) -> some View {
        let presentation = LeftRailNotificationPresentation(notification: notification)

        return HStack(alignment: .top, spacing: 6) {
            Button {
                onSelectNotification(notification.id)
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: presentation.systemImage)
                        .frame(width: 14)
                        .foregroundStyle(notification.level.badgeColor)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(presentation.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(notification.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(presentation.message)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if presentation.showsAcknowledge {
                Button {
                    onAcknowledgeNotification(notification.id)
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Acknowledge notification")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    var visibleNotifications: [WorkspaceNotification] {
        Array(leftRailNotifications.prefix(3))
    }

    var leftRailNotifications: [WorkspaceNotification] {
        notifications.filter { notification in
            notification.routing.shouldShowInLeftRail
                && (workspace == nil || notification.workspaceID == workspace?.id)
        }
    }

    var notificationSummary: LeftRailNotificationSummary {
        LeftRailNotificationSummary.make(from: leftRailNotifications)
    }

    var panelSummaries: [PanelLeafSummary] {
        rootNode.leafSummaries(focusedPanelID: focusedPanelID)
    }
}

private extension NotificationLevel {
    var badgeColor: Color {
        switch self {
        case .info:
            .blue
        case .warning:
            .yellow
        case .error:
            .red
        case .critical:
            .purple
        }
    }
}
