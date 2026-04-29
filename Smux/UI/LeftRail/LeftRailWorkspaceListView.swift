import SwiftUI

struct LeftRailWorkspaceListView: View {
    var activeWorkspace: Workspace?
    var workspaces: [Workspace]
    var recentWorkspaces: [RecentWorkspace]
    var onSelectWorkspace: (Workspace.ID) -> Void
    var onCloseWorkspace: (Workspace.ID) -> Void
    var onOpenRecentWorkspace: (RecentWorkspace) -> Void

    @State private var hoveredWorkspaceID: Workspace.ID?
    @State private var hoveredRecentWorkspaceID: RecentWorkspace.ID?

    var body: some View {
        LeftRailSectionView(title: "Workspaces", count: workspaces.count) {
            VStack(alignment: .leading, spacing: 8) {
                if workspaces.isEmpty {
                    LeftRailEmptyLine(text: "No open workspaces")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(workspaces) { listedWorkspace in
                            workspaceRow(listedWorkspace)
                        }
                    }
                }

                recentWorkspacesView
            }
        }
    }

    @ViewBuilder
    private var recentWorkspacesView: some View {
        if !recentWorkspaces.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)

                ForEach(recentWorkspaces.prefix(3)) { recentWorkspace in
                    recentWorkspaceRow(recentWorkspace)
                }
            }
        }
    }

    private func workspaceRow(_ listedWorkspace: Workspace) -> some View {
        let isActive = listedWorkspace.id == activeWorkspace?.id
        let isHovered = hoveredWorkspaceID == listedWorkspace.id

        return HStack(spacing: 4) {
            Button {
                onSelectWorkspace(listedWorkspace.id)
            } label: {
                HStack(spacing: 9) {
                    LeftRailLeadingIndicator(isActive: isActive)

                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16)
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(listedWorkspace.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Text(workspaceDetailText(listedWorkspace))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)
                }
                .padding(.vertical, 7)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? .primary : .secondary)
            .accessibilityLabel("Switch to \(listedWorkspace.displayName)")

            Button {
                onCloseWorkspace(listedWorkspace.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(isHovered || isActive ? 1 : 0.45)
            .help("Close workspace")
            .accessibilityLabel("Close \(listedWorkspace.displayName)")
        }
        .padding(.trailing, 4)
        .background(LeftRailRowBackground(isActive: isActive, isHovered: isHovered))
        .contentShape(RoundedRectangle(cornerRadius: LeftRailLayoutMetrics.rowCornerRadius, style: .continuous))
        .onHover { isHovering in
            hoveredWorkspaceID = isHovering ? listedWorkspace.id : nil
        }
    }

    private func recentWorkspaceRow(_ recentWorkspace: RecentWorkspace) -> some View {
        let isHovered = hoveredRecentWorkspaceID == recentWorkspace.id

        return Button {
            onOpenRecentWorkspace(recentWorkspace)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recentWorkspace.displayName)
                        .font(.caption)
                        .lineLimit(1)

                    Text(recentWorkspace.rootURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(LeftRailRowBackground(isActive: false, isHovered: isHovered))
        .contentShape(RoundedRectangle(cornerRadius: LeftRailLayoutMetrics.rowCornerRadius, style: .continuous))
        .onHover { isHovering in
            hoveredRecentWorkspaceID = isHovering ? recentWorkspace.id : nil
        }
    }

    private func workspaceDetailText(_ workspace: Workspace) -> String {
        if let gitBranch = workspace.gitBranch {
            return gitBranch
        }

        return workspace.rootURL.path
    }
}
