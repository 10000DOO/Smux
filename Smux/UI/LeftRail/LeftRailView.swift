import SwiftUI

struct LeftRailView: View {
    var workspace: Workspace?
    var notifications: [WorkspaceNotification]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace?.displayName ?? "No Workspace")
                    .font(.headline)
                    .lineLimit(1)
                Text(workspace?.rootURL.lastPathComponent ?? "Smux")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            Label("Files", systemImage: "folder")
                .font(.subheadline)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Status", systemImage: "bell")
                    .font(.subheadline)

                ForEach(notifications.prefix(3)) { notification in
                    Text(notification.message)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
