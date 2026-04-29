import SwiftUI

struct LeftRailSessionListView: View {
    var sessionItems: [LeftRailSessionPresentation]
    var onCreateSession: () -> Void
    var onSelectSession: (WorkspaceLayoutSession.ID) -> Void
    var onCloseSession: (WorkspaceLayoutSession.ID) -> Void

    @State private var hoveredSessionID: WorkspaceLayoutSession.ID?

    var body: some View {
        LeftRailSectionView(title: "Sessions", count: sessionItems.count) {
            Button(action: onCreateSession) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New session")
            .accessibilityLabel("New session")
        } content: {
            if sessionItems.isEmpty {
                LeftRailEmptyLine(text: "No sessions")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sessionItems) { sessionItem in
                        sessionRow(sessionItem)
                    }
                }
            }
        }
    }

    private func sessionRow(_ sessionItem: LeftRailSessionPresentation) -> some View {
        let isHovered = hoveredSessionID == sessionItem.id

        return HStack(spacing: 4) {
            Button {
                onSelectSession(sessionItem.id)
            } label: {
                HStack(spacing: 9) {
                    LeftRailLeadingIndicator(isActive: sessionItem.isFocused)

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
                    LeftRailBadge(count: sessionItem.badgeCount)
                }
                .padding(.vertical, 7)
                .padding(.leading, 0)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
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
            .opacity(isHovered || sessionItem.isFocused ? 1 : 0.45)
            .help("Close session")
            .accessibilityLabel("Close \(sessionItem.title)")
        }
        .padding(.trailing, 4)
        .background(LeftRailRowBackground(isActive: sessionItem.isFocused, isHovered: isHovered))
        .contentShape(RoundedRectangle(cornerRadius: LeftRailLayoutMetrics.rowCornerRadius, style: .continuous))
        .onHover { isHovering in
            hoveredSessionID = isHovering ? sessionItem.id : nil
        }
    }
}
