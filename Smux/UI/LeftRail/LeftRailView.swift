import SwiftUI

struct LeftRailView: View {
    var workspace: Workspace?
    var rootNode: PanelNode
    var focusedPanelID: PanelNode.ID?
    var notifications: [WorkspaceNotification]
    var fileTreeRoot: FileTreeNode? = nil
    var selectedFileTreeNodeID: FileTreeNode.ID? = nil
    var onExpandFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }
    var onSelectFileTreeNode: (FileTreeNode.ID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceSummary

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
            Label("Latest", systemImage: "bell")
                .font(.subheadline)

            if visibleNotifications.isEmpty {
                Text("No notifications")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleNotifications) { notification in
                    Text(notification.message)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var visibleNotifications: [WorkspaceNotification] {
        Array(notifications.filter(\.routing.shouldShowInLeftRail).prefix(3))
    }

    var panelSummaries: [PanelLeafSummary] {
        rootNode.leafSummaries(focusedPanelID: focusedPanelID)
    }
}
