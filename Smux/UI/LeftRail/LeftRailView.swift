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
    var onSelectSession: (WorkspaceSession.ID) -> Void = { _ in }
    var onCloseSession: (WorkspaceSession.ID) -> Void = { _ in }
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
                collapsedBody
            } else {
                expandedBody
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension LeftRailView {
    var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            expandedHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionSection
                    workspaceSection
                    fileTreeSection
                    notificationSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
    }

    var collapsedBody: some View {
        VStack(spacing: 10) {
            railIconButton(systemImage: "sidebar.left", help: "Expand sidebar", action: onToggleCollapsed)
                .padding(.top, 10)

            railIconButton(systemImage: "plus", help: "Add workspace", action: onOpenWorkspace)

            Divider()
                .padding(.horizontal, 10)

            ForEach(sessionItems) { sessionItem in
                Button {
                    onSelectSession(sessionItem.id)
                } label: {
                    Image(systemName: sessionItem.systemImage)
                        .font(.system(size: 14, weight: sessionItem.isFocused ? .semibold : .regular))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(sessionItem.isFocused ? Color.primary : Color.secondary)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(sessionItem.isFocused ? Color.secondary.opacity(0.14) : Color.clear)
                        }
                        .overlay(alignment: .topTrailing) {
                            compactBadge(count: sessionItem.badgeCount)
                        }
                }
                .buttonStyle(.plain)
                .help(sessionItem.title)
            }

            Spacer(minLength: 12)

            Button {
                if let notificationID = visibleNotifications.first?.id {
                    onSelectNotification(notificationID)
                }
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(visibleNotifications.isEmpty ? Color.secondary.opacity(0.45) : Color.secondary)
                    .overlay(alignment: .topTrailing) {
                        compactBadge(count: notificationSummary.totalCount)
                    }
            }
            .buttonStyle(.plain)
            .disabled(visibleNotifications.isEmpty)
            .help("Latest notification")
            .padding(.bottom, 10)
        }
    }

    var expandedHeader: some View {
        HStack(spacing: 8) {
            Button(action: onToggleCollapsed) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Collapse sidebar")

            VStack(alignment: .leading, spacing: 1) {
                Text(workspace?.displayName ?? "No Workspace")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(workspaceSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onOpenWorkspace) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.primary)
            .help("Add workspace")
            .accessibilityLabel("Add workspace")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    var workspaceSubtitle: String {
        if let gitBranch = workspace?.gitBranch {
            return gitBranch
        }

        return workspace?.rootURL.path ?? "Smux"
    }

    var sessionSection: some View {
        railSection(title: "Sessions", count: sessionItems.count) {
            if sessionItems.isEmpty {
                emptyLine("No sessions")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sessionItems) { sessionItem in
                        sessionRow(sessionItem)
                    }
                }
            }
        }
    }

    func sessionRow(_ sessionItem: LeftRailSessionPresentation) -> some View {
        HStack(spacing: 4) {
            Button {
                onSelectSession(sessionItem.id)
            } label: {
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(sessionItem.isFocused ? Color.accentColor : Color.clear)
                        .frame(width: 3)
                        .clipShape(Capsule())

                    Image(systemName: sessionItem.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(sessionItem.isFocused ? Color.primary : Color.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionItem.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(sessionItem.latestNotificationMessage ?? sessionItem.metadataText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)
                    sessionBadge(count: sessionItem.badgeCount)
                }
                .padding(.vertical, 7)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(sessionItem.isFocused ? Color.secondary.opacity(0.12) : Color.clear)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel(sessionItem.title)

            Button {
                onCloseSession(sessionItem.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Close session")
            .accessibilityLabel("Close \(sessionItem.title)")
        }
    }

    var workspaceSection: some View {
        railSection(title: "Workspaces", count: workspaces.count) {
            if workspaces.isEmpty {
                emptyLine("No open workspaces")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(workspaces) { listedWorkspace in
                        workspaceRow(listedWorkspace)
                    }
                }
            }

            if !recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)

                    ForEach(recentWorkspaces.prefix(3)) { recentWorkspace in
                        Button {
                            onOpenRecentWorkspace(recentWorkspace)
                        } label: {
                            Label(recentWorkspace.displayName, systemImage: "clock")
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func workspaceRow(_ listedWorkspace: Workspace) -> some View {
        HStack(spacing: 6) {
            Button {
                onSelectWorkspace(listedWorkspace.id)
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(listedWorkspace.id == workspace?.id ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                    Text(listedWorkspace.displayName)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                onCloseWorkspace(listedWorkspace.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Close workspace")
        }
        .font(.caption)
        .foregroundStyle(listedWorkspace.id == workspace?.id ? .primary : .secondary)
        .padding(.vertical, 3)
    }

    var fileTreeSection: some View {
        railSection(title: "Files", count: nil) {
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

    var notificationSection: some View {
        railSection(title: "Activity", count: notificationSummary.totalCount) {
            notificationStatusChips

            if visibleNotifications.isEmpty {
                emptyLine("No notifications")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleNotifications) { notification in
                        notificationRow(notification)
                    }
                }
            }
        }
    }

    func railSection<Content: View>(
        title: String,
        count: Int?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            content()
        }
    }

    @ViewBuilder
    var notificationStatusChips: some View {
        if !notificationSummary.items.isEmpty {
            HStack(spacing: 5) {
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
        }
    }

    func notificationRow(_ notification: WorkspaceNotification) -> some View {
        let presentation = LeftRailNotificationPresentation(notification: notification)

        return HStack(alignment: .top, spacing: 7) {
            Button {
                onSelectNotification(notification.id)
            } label: {
                HStack(alignment: .top, spacing: 7) {
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
                            .font(.caption)
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
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Acknowledge notification")
            }
        }
        .foregroundStyle(.secondary)
    }

    func railIconButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    @ViewBuilder
    func sessionBadge(count: Int) -> some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .background(Color.red, in: Capsule())
        }
    }

    @ViewBuilder
    func compactBadge(count: Int) -> some View {
        if count > 0 {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .offset(x: 1, y: -1)
        }
    }

    func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
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
