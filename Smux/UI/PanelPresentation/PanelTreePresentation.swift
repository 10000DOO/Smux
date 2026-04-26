import Foundation

nonisolated struct PanelLeafSummary: Identifiable, Hashable {
    var id: PanelNode.ID
    var surface: PanelSurfaceDescriptor
    var isFocused: Bool
}

nonisolated struct PanelNotificationBadgeSummary: Equatable {
    static func unacknowledgedBadgeCount(
        for panelID: PanelNode.ID,
        notifications: [WorkspaceNotification]
    ) -> Int {
        notifications.filter {
            $0.routing.panelID == panelID
                && $0.routing.shouldBadgePanel
                && $0.acknowledgedAt == nil
        }.count
    }
}

nonisolated struct LeftRailPanelTabPresentation: Identifiable, Equatable {
    var id: PanelNode.ID
    var title: String
    var metadataText: String
    var latestNotificationMessage: String?
    var systemImage: String
    var isFocused: Bool
    var badgeCount: Int

    init(
        panel: PanelLeafSummary,
        workspace: Workspace?,
        notifications: [WorkspaceNotification]
    ) {
        let surfacePresentation = PanelSurfacePresentation(surface: panel.surface)

        id = panel.id
        title = surfacePresentation.title
        metadataText = Self.metadataText(for: workspace)
        latestNotificationMessage = Self.latestNotificationMessage(
            for: panel.id,
            notifications: notifications
        )
        systemImage = surfacePresentation.systemImage
        isFocused = panel.isFocused
        badgeCount = PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
            for: panel.id,
            notifications: notifications
        )
    }

    private static func metadataText(for workspace: Workspace?) -> String {
        guard let workspace else {
            return "No workspace"
        }

        let rootName = workspace.rootURL.lastPathComponent
        if let gitBranch = workspace.gitBranch {
            return "\(gitBranch) - \(rootName)"
        }

        return rootName
    }

    private static func latestNotificationMessage(
        for panelID: PanelNode.ID,
        notifications: [WorkspaceNotification]
    ) -> String? {
        notifications
            .filter {
                $0.routing.panelID == panelID
                    && $0.routing.shouldShowInLeftRail
                    && $0.acknowledgedAt == nil
            }
            .max { first, second in
                first.createdAt < second.createdAt
            }?
            .message
    }
}

extension PanelNode {
    func leafSummaries(focusedPanelID: PanelNode.ID?) -> [PanelLeafSummary] {
        if isLeaf {
            return [
                PanelLeafSummary(
                    id: id,
                    surface: surface ?? .empty,
                    isFocused: focusedPanelID == id
                )
            ]
        }

        return children.flatMap { $0.leafSummaries(focusedPanelID: focusedPanelID) }
    }

    var leafCount: Int {
        leafSummaries(focusedPanelID: nil).count
    }
}
