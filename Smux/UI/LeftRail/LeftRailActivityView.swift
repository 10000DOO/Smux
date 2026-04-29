import SwiftUI

struct LeftRailActivityView: View {
    var notificationSummary: LeftRailNotificationSummary
    var visibleNotifications: [WorkspaceNotification]
    var onSelectNotification: (WorkspaceNotification.ID) -> Void
    var onAcknowledgeNotification: (WorkspaceNotification.ID) -> Void

    @State private var hoveredNotificationID: WorkspaceNotification.ID?

    var body: some View {
        LeftRailSectionView(title: "Activity", count: notificationSummary.totalCount) {
            VStack(alignment: .leading, spacing: 8) {
                notificationStatusChips

                if visibleNotifications.isEmpty {
                    LeftRailEmptyLine(text: "No notifications")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(visibleNotifications) { notification in
                            notificationRow(notification)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notificationStatusChips: some View {
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
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .help(item.title)
                }
            }
        }
    }

    private func notificationRow(_ notification: WorkspaceNotification) -> some View {
        let presentation = LeftRailNotificationPresentation(notification: notification)
        let isHovered = hoveredNotificationID == notification.id

        return HStack(alignment: .top, spacing: 4) {
            Button {
                onSelectNotification(notification.id)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: presentation.systemImage)
                        .font(.system(size: 12, weight: .medium))
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
                .padding(.vertical, 7)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if presentation.showsAcknowledge {
                Button {
                    onAcknowledgeNotification(notification.id)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0.55)
                .help("Acknowledge notification")
            }
        }
        .padding(.trailing, 4)
        .foregroundStyle(.secondary)
        .background(LeftRailRowBackground(isActive: false, isHovered: isHovered))
        .contentShape(RoundedRectangle(cornerRadius: LeftRailLayoutMetrics.rowCornerRadius, style: .continuous))
        .onHover { isHovering in
            hoveredNotificationID = isHovering ? notification.id : nil
        }
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
