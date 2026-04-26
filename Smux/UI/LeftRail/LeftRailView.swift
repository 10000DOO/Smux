import SwiftUI

struct LeftRailView: View {
    var workspace: Workspace?
    var workspaces: [Workspace] = []
    var recentWorkspaces: [RecentWorkspace] = []
    var panelTabs: [LeftRailPanelTabPresentation] = []
    var notificationSummary: LeftRailNotificationSummary = .empty
    var visibleNotifications: [WorkspaceNotification] = []
    var fileTreeRoot: FileTreeNode? = nil
    var selectedFileTreeNodeID: FileTreeNode.ID? = nil
    var onExpandFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onSelectFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onSelectPanel: (PanelNode.ID) -> Void = { _ in }
    var onOpenWorkspace: () -> Void = {}
    var onSelectWorkspace: (Workspace.ID) -> Void = { _ in }
    var onCloseWorkspace: (Workspace.ID) -> Void = { _ in }
    var onOpenRecentWorkspace: (RecentWorkspace) -> Void = { _ in }
    var onSelectNotification: (WorkspaceNotification.ID) -> Void = { _ in }
    var onAcknowledgeNotification: (WorkspaceNotification.ID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            railToolbar

            workspaceSummary

            Divider()

            panelsSummary

            Divider()

            workspaceList

            Divider()

            fileTreeSection

            Spacer()

            latestNotifications
        }
        .padding(12)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension LeftRailView {
    var railToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
                .help("Left rail")

            Button {
                if let notificationID = visibleNotifications.first?.id {
                    onSelectNotification(notificationID)
                }
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .overlay(alignment: .topTrailing) {
                        notificationToolbarBadge
                    }
            }
            .buttonStyle(.plain)
            .disabled(visibleNotifications.isEmpty)
            .foregroundStyle(visibleNotifications.isEmpty ? .tertiary : .secondary)
            .help("Open latest notification")

            Spacer()

            Button(action: onOpenWorkspace) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Color.accentColor)
            .help("Open workspace")
            .accessibilityLabel("Open workspace")
        }
    }

    @ViewBuilder
    var notificationToolbarBadge: some View {
        if notificationSummary.totalCount > 0 {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .offset(x: 1, y: -1)
        }
    }

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
            HStack {
                Label("Panels", systemImage: "rectangle.split.3x1")
                    .font(.subheadline)
                Spacer()
                Text("\(panelTabs.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if panelTabs.isEmpty {
                Text("No panels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(panelTabs) { panelTab in
                            panelTabButton(panelTab)
                        }
                    }
                }
                .frame(maxHeight: 230, alignment: .topLeading)
            }
        }
    }

    func panelTabButton(_ panelTab: LeftRailPanelTabPresentation) -> some View {
        Button {
            onSelectPanel(panelTab.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: panelTab.systemImage)
                        .frame(width: 15)

                    Text(panelTab.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    panelBadge(count: panelTab.badgeCount, isFocused: panelTab.isFocused)
                }

                Text(panelTab.metadataText)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(panelTab.isFocused ? Color.white.opacity(0.82) : Color.secondary)

                if let latestNotificationMessage = panelTab.latestNotificationMessage {
                    Text(latestNotificationMessage)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(panelTab.isFocused ? Color.white : Color.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .foregroundStyle(panelTab.isFocused ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(panelTab.isFocused ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        panelTab.isFocused ? Color.white.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.35),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: panelTab.isFocused ? Color.accentColor.opacity(0.16) : Color.clear,
                radius: 5,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panelTab.title)
    }

    @ViewBuilder
    func panelBadge(count: Int, isFocused: Bool) -> some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isFocused ? Color.accentColor : Color.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .background(isFocused ? Color.white : Color.red, in: Capsule())
                .accessibilityLabel("\(count) unacknowledged panel notifications")
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
