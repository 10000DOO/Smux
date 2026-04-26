import SwiftUI

struct WorkspaceShellView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var panelStore: PanelStore
    @ObservedObject var notificationStore: NotificationStore
    @ObservedObject var recentWorkspaceStore: RecentWorkspaceStore
    @ObservedObject var fileTreeStore: FileTreeStore
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var documentFileWatchStore: DocumentFileWatchStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var previewPreferencesStore: PreviewPreferencesStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @ObservedObject var terminalSessionController: TerminalSessionController
    @ObservedObject var terminalOutputStore: TerminalOutputStore
    @ObservedObject var terminalPreferencesStore: TerminalPreferencesStore
    @ObservedObject var workspaceSessionStore: WorkspaceSessionStore
    var commandRouter: AppCommandRouter
    var onOpenWorkspace: () -> Void = {}
    @State private var isLeftRailCollapsed = false
    @State private var leftRailWidth = WorkspaceShellMetrics.defaultLeftRailWidth
    @State private var leftRailDragStartWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            LeftRailView(
                workspace: workspaceStore.activeWorkspace,
                workspaces: workspaceStore.workspaces,
                recentWorkspaces: recentWorkspaceStore.recentWorkspaces,
                panelTabs: leftRailPanelTabs,
                notificationSummary: leftRailNotificationSummary,
                visibleNotifications: visibleLeftRailNotifications,
                fileTreeRoot: fileTreeStore.root,
                selectedFileTreeNodeID: fileTreeStore.selectedNodeID,
                isCollapsed: isLeftRailCollapsed,
                onExpandFileTreeNode: expandFileTreeNode,
                onSelectFileTreeNode: selectFileTreeNode,
                onSelectPanel: { commandRouter.focus(panelID: $0) },
                onOpenWorkspace: onOpenWorkspace,
                onToggleCollapsed: {
                    isLeftRailCollapsed.toggle()
                },
                onSelectWorkspace: selectWorkspace,
                onCloseWorkspace: closeWorkspace,
                onOpenRecentWorkspace: openRecentWorkspace,
                onSelectNotification: activateNotification,
                onAcknowledgeNotification: acknowledgeNotification
            )
            .frame(width: isLeftRailCollapsed ? WorkspaceShellMetrics.collapsedLeftRailWidth : leftRailWidth)

            WorkspaceShellResizeHandle(isActive: !isLeftRailCollapsed)
                .gesture(leftRailResizeGesture)

            SplitPanelView(
                node: panelStore.rootNode,
                focusedPanelID: panelStore.focusedPanelID,
                selectedDocumentURL: fileTreeStore.selectedDocumentCandidateURL,
                documentSessionStore: documentSessionStore,
                documentFileWatchStore: documentFileWatchStore,
                previewSessionStore: previewSessionStore,
                previewPreferencesStore: previewPreferencesStore,
                documentTextStore: documentTextStore,
                terminalSessionController: terminalSessionController,
                terminalOutputStore: terminalOutputStore,
                terminalPreferencesStore: terminalPreferencesStore,
                workspaceSessionStore: workspaceSessionStore,
                notifications: activeWorkspaceNotifications,
                onFocus: { commandRouter.focus(panelID: $0) },
                onSplit: { panelID, direction in
                    commandRouter.splitPanel(panelID: panelID, direction: direction, surface: .empty)
                },
                onCreateTerminal: createTerminal,
                onOpenSelectedDocument: { panelID, preferredSurface in
                    openSelectedDocument(in: panelID, preferredSurface: preferredSurface)
                },
                onUpdateSplitRatio: { splitID, ratio in
                    commandRouter.updateSplitRatio(splitID: splitID, ratio: ratio)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .topLeading) {
            WorkspaceCommandShortcutLayer(
                commandRouter: commandRouter,
                activeWorkspaceID: workspaceStore.activeWorkspace?.id,
                focusedPanelID: panelStore.focusedPanelID,
                canCloseFocusedPanel: panelStore.canCloseFocusedPanel,
                selectedDocumentURL: fileTreeStore.selectedDocumentCandidateURL,
                latestNotificationID: (workspaceStore.activeWorkspace?.id).flatMap { workspaceID in
                    notificationStore.mostRecentVisibleNotificationID(workspaceID: workspaceID)
                },
                onActivateNotification: activateNotification,
                onCommandError: { message in
                    workspaceStore.openErrorMessage = message
                }
            )
        }
        .alert(
            "Smux",
            isPresented: Binding(
                get: { workspaceStore.openErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        workspaceStore.clearOpenError()
                    }
                }
            )
        ) {
            Button("OK") {
                workspaceStore.clearOpenError()
            }
        } message: {
            Text(workspaceStore.openErrorMessage ?? "")
        }
        .task(id: workspaceStore.activeWorkspace?.id) {
            await loadFileTreeForActiveWorkspace()
        }
    }

    private var leftRailResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isLeftRailCollapsed else {
                    return
                }

                if leftRailDragStartWidth == nil {
                    leftRailDragStartWidth = leftRailWidth
                }

                let proposedWidth = (leftRailDragStartWidth ?? leftRailWidth) + value.translation.width
                leftRailWidth = WorkspaceShellMetrics.clampedLeftRailWidth(proposedWidth)
            }
            .onEnded { _ in
                leftRailDragStartWidth = nil
            }
    }
}

private enum WorkspaceShellMetrics {
    static let collapsedLeftRailWidth: CGFloat = 54
    static let defaultLeftRailWidth: CGFloat = 300
    static let minimumLeftRailWidth: CGFloat = 220
    static let maximumLeftRailWidth: CGFloat = 420

    static func clampedLeftRailWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumLeftRailWidth), maximumLeftRailWidth)
    }
}

private struct WorkspaceShellResizeHandle: View {
    var isActive: Bool
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(isHovering && isActive ? 0.22 : 0.08))
                .frame(width: 1)

            Capsule()
                .fill(Color.secondary.opacity(isHovering && isActive ? 0.35 : 0))
                .frame(width: 3, height: 48)
        }
        .frame(width: isActive ? 9 : 1)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            guard isActive else {
                return
            }

            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityLabel("Resize sidebar")
        .accessibilityHint("Drag to resize the session sidebar")
    }
}

private struct WorkspaceCommandShortcutLayer: View {
    var commandRouter: AppCommandRouter
    var activeWorkspaceID: Workspace.ID?
    var focusedPanelID: PanelNode.ID?
    var canCloseFocusedPanel: Bool
    var selectedDocumentURL: URL?
    var latestNotificationID: WorkspaceNotification.ID?
    var onActivateNotification: (WorkspaceNotification.ID) -> Void
    var onCommandError: (String) -> Void

    var body: some View {
        Group {
            shortcutButton("Focus Next Panel") {
                commandRouter.focusNextPanel()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            shortcutButton("Focus Previous Panel") {
                commandRouter.focusPreviousPanel()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            shortcutButton("Split Panel Horizontally") {
                commandRouter.splitFocusedPanel(direction: .vertical, surface: .empty)
            }
            .keyboardShortcut("-", modifiers: [.command, .shift])

            shortcutButton("Split Panel Vertically") {
                commandRouter.splitFocusedPanel(direction: .horizontal, surface: .empty)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])

            shortcutButton("New Panel") {
                commandRouter.createPanel(splitDirection: .horizontal, surface: .empty)
            }
            .keyboardShortcut("t", modifiers: [.command])

            shortcutButton("New Panel Below") {
                commandRouter.createPanel(splitDirection: .vertical, surface: .empty)
            }
            .keyboardShortcut("d", modifiers: [.command])

            if canCloseFocusedPanel {
                shortcutButton("Close Current Panel") {
                    commandRouter.closeFocusedPanel()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            shortcutButton("Create Terminal") {
                createTerminal()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            shortcutButton("Open Selected File in New Editor Panel") {
                openSelectedDocumentInNewPanel(preferredSurface: .editor)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            shortcutButton("Open Selected File in New Preview Panel") {
                openSelectedDocumentInNewPanel(preferredSurface: .preview)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            shortcutButton("Activate Most Recent Notification") {
                activateMostRecentNotification()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func shortcutButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
    }

    private func createTerminal() {
        guard let activeWorkspaceID else {
            onCommandError("No workspace is currently active.")
            return
        }

        Task { @MainActor in
            do {
                if let focusedPanelID {
                    try await commandRouter.createTerminal(in: activeWorkspaceID, replacingPanel: focusedPanelID)
                } else {
                    try await commandRouter.createTerminal(in: activeWorkspaceID)
                }
            } catch {
                onCommandError("Failed to create terminal: \(error.localizedDescription)")
            }
        }
    }

    private func openSelectedDocumentInNewPanel(preferredSurface: DocumentOpenMode) {
        guard let selectedDocumentURL else {
            onCommandError("Select a Markdown or Mermaid file first.")
            return
        }

        Task { @MainActor in
            do {
                try await commandRouter.openDocumentInNewPanel(
                    selectedDocumentURL,
                    preferredSurface: preferredSurface,
                    splitDirection: .horizontal
                )
            } catch {
                onCommandError("Failed to open document: \(error.localizedDescription)")
            }
        }
    }

    private func activateMostRecentNotification() {
        guard activeWorkspaceID != nil else {
            onCommandError("No workspace is currently active.")
            return
        }

        guard let latestNotificationID else {
            onCommandError("No visible notifications in the active workspace.")
            return
        }

        onActivateNotification(latestNotificationID)
    }
}

private extension WorkspaceShellView {
    var activeWorkspaceNotifications: [WorkspaceNotification] {
        WorkspaceShellNotificationFilter.activeWorkspaceNotifications(
            notificationStore.notifications,
            activeWorkspaceID: workspaceStore.activeWorkspace?.id
        )
    }

    var leftRailPanelTabs: [LeftRailPanelTabPresentation] {
        panelStore.rootNode
            .leafSummaries(focusedPanelID: panelStore.focusedPanelID)
            .map { panel in
                LeftRailPanelTabPresentation(
                    panel: panel,
                    session: panel.surface.sessionID.flatMap { workspaceSessionStore.session(for: $0) },
                    workspace: workspaceStore.activeWorkspace,
                    notifications: activeWorkspaceNotifications
                )
            }
    }

    var visibleLeftRailNotifications: [WorkspaceNotification] {
        Array(leftRailNotifications.prefix(3))
    }

    var leftRailNotificationSummary: LeftRailNotificationSummary {
        LeftRailNotificationSummary.make(from: leftRailNotifications)
    }

    var leftRailNotifications: [WorkspaceNotification] {
        WorkspaceShellNotificationFilter.leftRailNotifications(from: activeWorkspaceNotifications)
    }

    func loadFileTreeForActiveWorkspace() async {
        guard let workspace = workspaceStore.activeWorkspace else {
            fileTreeStore.clear()
            return
        }

        do {
            try await fileTreeStore.loadRoot(workspace: workspace)
        } catch is CancellationError {
            return
        } catch {
            workspaceStore.openErrorMessage = "Failed to load file tree: \(error.localizedDescription)"
        }
    }

    func selectWorkspace(id: Workspace.ID) {
        guard let workspace = workspaceStore.workspaces.first(where: { $0.id == id }) else {
            return
        }

        Task { @MainActor in
            do {
                try await commandRouter.openWorkspace(rootURL: workspace.rootURL)
            } catch {
                workspaceStore.openErrorMessage = "Failed to switch workspace: \(error.localizedDescription)"
            }
        }
    }

    func closeWorkspace(id: Workspace.ID) {
        Task { @MainActor in
            do {
                try await commandRouter.closeWorkspace(id: id)
            } catch {
                workspaceStore.openErrorMessage = "Failed to close workspace: \(error.localizedDescription)"
            }
        }
    }

    func openRecentWorkspace(_ recentWorkspace: RecentWorkspace) {
        Task { @MainActor in
            do {
                try await commandRouter.openWorkspace(rootURL: recentWorkspace.rootURL)
            } catch {
                workspaceStore.openErrorMessage = "Failed to open recent workspace: \(error.localizedDescription)"
            }
        }
    }

    func activateNotification(id notificationID: WorkspaceNotification.ID) {
        guard let notification = notificationStore.notifications.first(where: { $0.id == notificationID }) else {
            return
        }

        if let panelID = notification.routing.panelID {
            commandRouter.focus(panelID: panelID)
        }
        notificationStore.acknowledge(id: notificationID)
    }

    func acknowledgeNotification(id notificationID: WorkspaceNotification.ID) {
        notificationStore.acknowledge(id: notificationID)
    }

    func expandFileTreeNode(_ nodeID: FileTreeNode.ID) {
        Task { @MainActor in
            do {
                try await fileTreeStore.expand(nodeID: nodeID)
            } catch {
                workspaceStore.openErrorMessage = "Failed to expand folder: \(error.localizedDescription)"
            }
        }
    }

    func selectFileTreeNode(_ nodeID: FileTreeNode.ID) {
        fileTreeStore.selectedNodeID = nodeID

        guard let node = fileTreeStore.root?.node(id: nodeID) else {
            return
        }

        switch node.kind {
        case .directory:
            expandFileTreeNode(nodeID)
        case .file:
            Task { @MainActor in
                do {
                    switch WorkspaceFileOpenPolicy.command(focusedSurface: panelStore.focusedSurface) {
                    case .replaceFocused(let preferredSurface):
                        try await commandRouter.openDocument(node.url, preferredSurface: preferredSurface)
                    case .openInNewPanel(let preferredSurface, let splitDirection):
                        try await commandRouter.openDocumentInNewPanel(
                            node.url,
                            preferredSurface: preferredSurface,
                            splitDirection: splitDirection
                        )
                    }
                } catch {
                    workspaceStore.openErrorMessage = "Failed to open document: \(error.localizedDescription)"
                }
            }
        }
    }

    func createTerminal(in panelID: PanelNode.ID) {
        guard let workspaceID = workspaceStore.activeWorkspace?.id else {
            workspaceStore.openErrorMessage = "No workspace is currently active."
            return
        }

        Task { @MainActor in
            do {
                try await commandRouter.createTerminal(in: workspaceID, replacingPanel: panelID)
            } catch {
                workspaceStore.openErrorMessage = "Failed to create terminal: \(error.localizedDescription)"
            }
        }
    }

    func openSelectedDocument(in panelID: PanelNode.ID, preferredSurface: DocumentOpenMode) {
        guard let selectedDocumentURL = fileTreeStore.selectedDocumentCandidateURL else {
            workspaceStore.openErrorMessage = "Select a Markdown or Mermaid file first."
            return
        }

        Task { @MainActor in
            do {
                try await commandRouter.openDocument(
                    selectedDocumentURL,
                    preferredSurface: preferredSurface,
                    replacingPanel: panelID
                )
            } catch {
                workspaceStore.openErrorMessage = "Failed to open document: \(error.localizedDescription)"
            }
        }
    }
}

nonisolated enum WorkspaceSelectedFileOpenCommand: Equatable {
    case replaceFocused(DocumentOpenMode)
    case openInNewPanel(DocumentOpenMode, SplitDirection)
}

nonisolated enum WorkspaceFileOpenPolicy {
    static func command(focusedSurface: PanelSurfaceDescriptor?) -> WorkspaceSelectedFileOpenCommand {
        if focusedSurface == .empty {
            return .replaceFocused(.split)
        }

        return .openInNewPanel(.split, .horizontal)
    }
}

nonisolated enum WorkspaceShellNotificationFilter {
    static func activeWorkspaceNotifications(
        _ notifications: [WorkspaceNotification],
        activeWorkspaceID: Workspace.ID?
    ) -> [WorkspaceNotification] {
        guard let activeWorkspaceID else {
            return notifications
        }

        return notifications.filter { $0.workspaceID == activeWorkspaceID }
    }

    static func leftRailNotifications(
        from notifications: [WorkspaceNotification]
    ) -> [WorkspaceNotification] {
        notifications.filter(\.routing.shouldShowInLeftRail)
    }
}

private extension FileTreeNode {
    func node(id targetID: ID) -> FileTreeNode? {
        if id == targetID {
            return self
        }

        guard case .loaded(let children) = childrenState else {
            return nil
        }

        for child in children {
            if let matchingNode = child.node(id: targetID) {
                return matchingNode
            }
        }

        return nil
    }
}
