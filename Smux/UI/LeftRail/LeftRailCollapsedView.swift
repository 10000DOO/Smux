import SwiftUI

struct LeftRailCollapsedView: View {
    var sessionItems: [LeftRailSessionPresentation]
    var notificationSummary: LeftRailNotificationSummary
    var visibleNotifications: [WorkspaceNotification]
    var onToggleCollapsed: () -> Void
    var onOpenWorkspace: () -> Void
    var onCreateSession: () -> Void
    var onSelectSession: (WorkspaceLayoutSession.ID) -> Void
    var onSelectNotification: (WorkspaceNotification.ID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            railIconButton(systemImage: "sidebar.left", help: "Expand sidebar", action: onToggleCollapsed)
                .padding(.top, 10)

            railIconButton(systemImage: "folder.badge.plus", help: "Add workspace", action: onOpenWorkspace)
            railIconButton(systemImage: "plus.square", help: "New session", action: onCreateSession)

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
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(sessionItem.isFocused ? Color.primary.opacity(0.095) : Color.clear)
                        }
                        .overlay(alignment: .topTrailing) {
                            LeftRailCompactBadge(count: sessionItem.badgeCount)
                        }
                }
                .buttonStyle(.plain)
                .help(sessionItem.title)
                .accessibilityLabel(sessionItem.title)
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
                        LeftRailCompactBadge(count: notificationSummary.totalCount)
                    }
            }
            .buttonStyle(.plain)
            .disabled(visibleNotifications.isEmpty)
            .help("Latest notification")
            .padding(.bottom, 10)
        }
    }

    private func railIconButton(
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
        .accessibilityLabel(help)
    }
}
