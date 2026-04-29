import SwiftUI

struct LeftRailHeaderView: View {
    var workspace: Workspace?
    var onToggleCollapsed: () -> Void
    var onOpenWorkspace: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCollapsed) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Collapse sidebar")
            .accessibilityLabel("Collapse sidebar")

            VStack(alignment: .leading, spacing: 2) {
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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help("Add workspace")
            .accessibilityLabel("Add workspace")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
        }
    }

    private var workspaceSubtitle: String {
        if let gitBranch = workspace?.gitBranch {
            return gitBranch
        }

        return workspace?.rootURL.path ?? "Smux"
    }
}
