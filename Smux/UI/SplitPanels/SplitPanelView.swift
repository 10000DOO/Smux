import SwiftUI

struct SplitPanelView: View {
    var node: PanelNode
    var focusedPanelID: PanelNode.ID?
    var selectedDocumentURL: URL?
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var documentFileWatchStore: DocumentFileWatchStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var previewPreferencesStore: PreviewPreferencesStore
    var previewRenderCoordinator: any PreviewRenderingCoordinating
    @ObservedObject var documentTextStore: DocumentTextStore
    @ObservedObject var terminalSessionController: TerminalSessionController
    @ObservedObject var terminalOutputStore: TerminalOutputStore
    @ObservedObject var terminalPreferencesStore: TerminalPreferencesStore
    @ObservedObject var workspaceSessionStore: WorkspaceSessionStore
    var notifications: [WorkspaceNotification] = []
    var onFocus: (PanelNode.ID) -> Void
    var onSplit: (PanelNode.ID, SplitDirection) -> Void
    var onCreateTerminal: (PanelNode.ID) -> Void
    var onOpenSelectedDocument: (PanelNode.ID, DocumentOpenMode) -> Void
    var onUpdateSplitRatio: (PanelNode.ID, Double) -> Void
    @State private var dragStartRatio: Double?

    var body: some View {
        switch node.kind {
        case .leaf:
            surfaceView(node.surface ?? .empty, panelID: node.id)
        case .split:
            splitView
        }
    }

    @ViewBuilder
    private var splitView: some View {
        if let direction = node.direction,
           let firstChild = node.children.first,
           node.children.count == 2,
           let secondChild = node.children.last {
            GeometryReader { proxy in
                switch direction {
                case .horizontal:
                    horizontalSplitView(
                        firstChild: firstChild,
                        secondChild: secondChild,
                        size: proxy.size
                    )
                case .vertical:
                    verticalSplitView(
                        firstChild: firstChild,
                        secondChild: secondChild,
                        size: proxy.size
                    )
                }
            }
        } else {
            surfaceView(.empty, panelID: node.id)
        }
    }

    private func horizontalSplitView(
        firstChild: PanelNode,
        secondChild: PanelNode,
        size: CGSize
    ) -> some View {
        let dividerLength = SplitPanelDivider.length
        let firstWidth = max(0, (size.width - dividerLength) * node.normalizedRatio)
        let secondWidth = max(0, size.width - dividerLength - firstWidth)

        return HStack(spacing: 0) {
            childView(firstChild)
                .frame(width: firstWidth, height: size.height)
            splitDivider(
                direction: .horizontal,
                length: size.height,
                axisLength: max(size.width - dividerLength, 1)
            )
            childView(secondChild)
                .frame(width: secondWidth, height: size.height)
        }
    }

    private func verticalSplitView(
        firstChild: PanelNode,
        secondChild: PanelNode,
        size: CGSize
    ) -> some View {
        let dividerLength = SplitPanelDivider.length
        let firstHeight = max(0, (size.height - dividerLength) * node.normalizedRatio)
        let secondHeight = max(0, size.height - dividerLength - firstHeight)

        return VStack(spacing: 0) {
            childView(firstChild)
                .frame(width: size.width, height: firstHeight)
            splitDivider(
                direction: .vertical,
                length: size.width,
                axisLength: max(size.height - dividerLength, 1)
            )
            childView(secondChild)
                .frame(width: size.width, height: secondHeight)
        }
    }

    private func childView(_ child: PanelNode) -> some View {
        SplitPanelView(
            node: child,
            focusedPanelID: focusedPanelID,
            selectedDocumentURL: selectedDocumentURL,
            documentSessionStore: documentSessionStore,
            documentFileWatchStore: documentFileWatchStore,
            previewSessionStore: previewSessionStore,
            previewPreferencesStore: previewPreferencesStore,
            previewRenderCoordinator: previewRenderCoordinator,
            documentTextStore: documentTextStore,
            terminalSessionController: terminalSessionController,
            terminalOutputStore: terminalOutputStore,
            terminalPreferencesStore: terminalPreferencesStore,
            workspaceSessionStore: workspaceSessionStore,
            notifications: notifications,
            onFocus: onFocus,
            onSplit: onSplit,
            onCreateTerminal: onCreateTerminal,
            onOpenSelectedDocument: onOpenSelectedDocument,
            onUpdateSplitRatio: onUpdateSplitRatio
        )
    }

    private func splitDivider(
        direction: SplitDirection,
        length: CGFloat,
        axisLength: CGFloat
    ) -> some View {
        SplitPanelDivider(direction: direction)
            .frame(
                width: direction == .horizontal ? SplitPanelDivider.length : length,
                height: direction == .horizontal ? length : SplitPanelDivider.length
            )
            .gesture(splitDragGesture(direction: direction, axisLength: axisLength))
    }

    private func splitDragGesture(direction: SplitDirection, axisLength: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartRatio == nil {
                    dragStartRatio = node.normalizedRatio
                }

                let delta = direction == .horizontal
                    ? value.translation.width
                    : value.translation.height
                let ratioDelta = Double(delta / axisLength)
                let newRatio = (dragStartRatio ?? node.normalizedRatio) + ratioDelta
                let minimumPixelRatio = min(0.45, Double(SplitPanelDivider.minimumPanelLength / axisLength))
                let pixelClampedRatio = min(max(newRatio, minimumPixelRatio), 1 - minimumPixelRatio)

                onUpdateSplitRatio(node.id, PanelNode.clampedRatio(pixelClampedRatio))
            }
            .onEnded { _ in
                dragStartRatio = nil
            }
    }

    @ViewBuilder
    private func surfaceView(_ surface: PanelSurfaceDescriptor, panelID: PanelNode.ID) -> some View {
        Group {
            switch surface {
            case .session(let sessionID):
                sessionSurfaceView(sessionID: sessionID, panelID: panelID)
            case .empty:
                PanelStartSurfaceView(
                    isFocused: focusedPanelID == panelID,
                    canOpenDocument: selectedDocumentURL != nil,
                    onCreateTerminal: {
                        onCreateTerminal(panelID)
                    },
                    onOpenEditor: {
                        onOpenSelectedDocument(panelID, .editor)
                    },
                    onOpenPreview: {
                        onOpenSelectedDocument(panelID, .preview)
                    },
                    onSplitRight: {
                        onSplit(panelID, .horizontal)
                    },
                    onSplitDown: {
                        onSplit(panelID, .vertical)
                    }
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .fill(focusedPanelID == panelID ? Color.accentColor.opacity(0.035) : Color.clear)
                .padding(4)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    focusedPanelID == panelID ? Color(nsColor: .separatorColor).opacity(0.28) : Color.clear,
                    lineWidth: 1
                )
                .padding(4)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            PanelNotificationBadgeView(
                count: PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
                    for: surface,
                    panelID: panelID,
                    notifications: notifications
                )
            )
            .padding(8)
        }
        .shadow(
            color: focusedPanelID == panelID ? Color.accentColor.opacity(0.08) : Color.clear,
            radius: 6
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus(panelID)
        }
    }

    @ViewBuilder
    private func sessionSurfaceView(sessionID: WorkspaceSession.ID, panelID: PanelNode.ID) -> some View {
        if let session = workspaceSessionStore.session(for: sessionID) {
            switch session.content {
            case .terminal(let terminalID):
                TerminalPanelSurfaceView(
                    sessionID: terminalID,
                    terminalSessionController: terminalSessionController,
                    terminalOutputStore: terminalOutputStore,
                    terminalPreferencesStore: terminalPreferencesStore,
                    onCreateTerminal: {
                        onCreateTerminal(panelID)
                    }
                )
                .id(sessionID)
            case .editor(let documentID):
                DocumentEditorPanelSurfaceView(
                    documentID: documentID,
                    isFocused: focusedPanelID == panelID,
                    documentSessionStore: documentSessionStore,
                    documentFileWatchStore: documentFileWatchStore,
                    documentTextStore: documentTextStore
                )
                .id(sessionID)
            case .preview(let previewID, _):
                PreviewPanelSurfaceView(
                    previewID: previewID,
                    documentSessionStore: documentSessionStore,
                    previewSessionStore: previewSessionStore,
                    previewPreferencesStore: previewPreferencesStore,
                    previewRenderCoordinator: previewRenderCoordinator,
                    documentTextStore: documentTextStore
                )
                .id(sessionID)
            }
        } else {
            MissingSessionPanelSurfaceView(sessionID: sessionID)
        }
    }
}

private struct MissingSessionPanelSurfaceView: View {
    var sessionID: WorkspaceSession.ID

    var body: some View {
        PlaceholderSurfaceView(
            title: "Missing Session",
            systemImage: "questionmark.square.dashed"
        )
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .help(sessionID.uuidString)
    }
}

private struct SplitPanelDivider: View {
    static let length: CGFloat = 8
    static let minimumPanelLength: CGFloat = 160

    var direction: SplitDirection
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(isHovering ? 0.18 : 0.08))

            Capsule()
                .fill(Color.secondary.opacity(isHovering ? 0.42 : 0.18))
                .frame(
                    width: direction == .horizontal ? 3 : 42,
                    height: direction == .horizontal ? 42 : 3
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                (direction == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
            .accessibilityLabel(direction == .horizontal ? "Resize columns" : "Resize rows")
            .accessibilityHint("Drag to resize adjacent panels")
    }
}

private struct PanelNotificationBadgeView: View {
    var count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .background(Color.red, in: Capsule())
                .accessibilityLabel("\(count) unacknowledged panel notifications")
        }
    }
}

private struct TerminalPanelSurfaceView: View {
    var sessionID: TerminalSession.ID
    @ObservedObject var terminalSessionController: TerminalSessionController
    @ObservedObject var terminalOutputStore: TerminalOutputStore
    @ObservedObject var terminalPreferencesStore: TerminalPreferencesStore
    var onCreateTerminal: () -> Void
    @StateObject private var viewModel: TerminalViewModel
    @State private var lastResizedGridSize: TerminalGridSizeEstimator?
    @State private var autoRefreshTracker = TerminalAutoRefreshTracker()

    init(
        sessionID: TerminalSession.ID,
        terminalSessionController: TerminalSessionController,
        terminalOutputStore: TerminalOutputStore,
        terminalPreferencesStore: TerminalPreferencesStore,
        onCreateTerminal: @escaping () -> Void
    ) {
        self.sessionID = sessionID
        self.terminalSessionController = terminalSessionController
        self.terminalOutputStore = terminalOutputStore
        self.terminalPreferencesStore = terminalPreferencesStore
        self.onCreateTerminal = onCreateTerminal
        _viewModel = StateObject(
            wrappedValue: TerminalViewModel(
                session: terminalSessionController.session(for: sessionID),
                terminalCore: terminalSessionController
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalPanelHeader(
                session: session,
                appearance: terminalPreferencesStore.appearance,
                onThemeChange: { terminalPreferencesStore.theme = $0 },
                onDecreaseFontSize: {
                    terminalPreferencesStore.adjustFontSize(by: -TerminalAppearance.fontSizeStep)
                },
                onResetFontSize: {
                    terminalPreferencesStore.resetFontSize()
                },
                onIncreaseFontSize: {
                    terminalPreferencesStore.adjustFontSize(by: TerminalAppearance.fontSizeStep)
                },
                onCreateTerminal: onCreateTerminal
            )

            SwiftTermTerminalViewRepresentable(
                outputSnapshot: terminalOutputStore.rawOutputSnapshot(for: sessionID),
                appearance: terminalPreferencesStore.appearance,
                onInput: viewModel.sendInput,
                onResize: resizeTerminal(columns:rows:)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            syncSession()
            refreshTerminatedSessionIfNeeded()
        }
        .onChange(of: terminalSessionController.sessions[sessionID]) {
            syncSession()
            refreshTerminatedSessionIfNeeded()
        }
    }

    private var session: TerminalSession? {
        terminalSessionController.sessions[sessionID]
    }

    private func syncSession() {
        viewModel.session = session
    }

    private func refreshTerminatedSessionIfNeeded() {
        if autoRefreshTracker.shouldRefresh(
            sessionID: sessionID,
            status: session?.status
        ) {
            onCreateTerminal()
        }
    }

    private func resizeTerminal(columns: Int, rows: Int) {
        let gridSize = TerminalGridSizeEstimator(columns: columns, rows: rows)
        guard lastResizedGridSize != gridSize else {
            return
        }

        lastResizedGridSize = gridSize
        terminalOutputStore.resize(sessionID: sessionID, columns: gridSize.columns, rows: gridSize.rows)
        viewModel.resize(columns: gridSize.columns, rows: gridSize.rows)
    }
}

nonisolated struct TerminalAutoRefreshTracker: Equatable {
    private(set) var refreshedSessionID: TerminalSession.ID?

    mutating func shouldRefresh(
        sessionID: TerminalSession.ID,
        status: TerminalSessionStatus?
    ) -> Bool {
        guard status == .terminated else {
            return false
        }

        guard refreshedSessionID != sessionID else {
            return false
        }

        refreshedSessionID = sessionID
        return true
    }
}

private struct TerminalPanelHeader: View {
    var session: TerminalSession?
    var appearance: TerminalAppearance
    var onThemeChange: (TerminalTheme) -> Void
    var onDecreaseFontSize: () -> Void
    var onResetFontSize: () -> Void
    var onIncreaseFontSize: () -> Void
    var onCreateTerminal: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
            Text(session?.title ?? "Terminal")
                .lineLimit(1)
            Spacer()
            Text(session?.status.rawValue.capitalized ?? "Missing")
                .foregroundStyle(.secondary)
            restartTerminalButton
            terminalThemeMenu
            terminalFontControls
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var restartTerminalButton: some View {
        if canCreateReplacementTerminal {
            Button(action: onCreateTerminal) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Open a new terminal in this panel")
            .accessibilityLabel("Open a new terminal in this panel")
        }
    }

    private var canCreateReplacementTerminal: Bool {
        guard let status = session?.status else {
            return true
        }

        return status == .terminated || status == .failed
    }

    private var terminalThemeMenu: some View {
        Menu {
            ForEach(TerminalTheme.allCases, id: \.self) { theme in
                Button(theme.title) {
                    onThemeChange(theme)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "paintbrush")
                Text(appearance.theme.statusText)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Terminal theme")
        .accessibilityLabel("Terminal theme")
    }

    private var terminalFontControls: some View {
        HStack(spacing: 6) {
            Button(action: onDecreaseFontSize) {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.borderless)
            .disabled(normalizedFontSize <= TerminalAppearance.minimumFontSize)
            .help("Decrease terminal font size")
            .accessibilityLabel("Decrease terminal font size")

            Button(action: onResetFontSize) {
                Text(fontSizeText)
                    .monospacedDigit()
                    .frame(minWidth: 34)
            }
            .buttonStyle(.borderless)
            .disabled(isDefaultFontSize)
            .help("Reset terminal font size")
            .accessibilityLabel("Reset terminal font size")

            Button(action: onIncreaseFontSize) {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.borderless)
            .disabled(normalizedFontSize >= TerminalAppearance.maximumFontSize)
            .help("Increase terminal font size")
            .accessibilityLabel("Increase terminal font size")
        }
    }

    private var normalizedFontSize: Double {
        TerminalAppearance.clampedFontSize(appearance.fontSize)
    }

    private var fontSizeText: String {
        "\(Int(normalizedFontSize.rounded()))pt"
    }

    private var isDefaultFontSize: Bool {
        abs(normalizedFontSize - TerminalAppearance.defaultFontSize) < 0.0001
    }
}

private struct DocumentEditorPanelSurfaceView: View {
    var documentID: DocumentSession.ID
    var isFocused: Bool
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var documentFileWatchStore: DocumentFileWatchStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @StateObject private var viewModel: DocumentEditorViewModel
    @State private var errorMessage: String?
    @State private var watchErrorMessage: String?

    init(
        documentID: DocumentSession.ID,
        isFocused: Bool,
        documentSessionStore: DocumentSessionStore,
        documentFileWatchStore: DocumentFileWatchStore,
        documentTextStore: DocumentTextStore
    ) {
        self.documentID = documentID
        self.isFocused = isFocused
        self.documentSessionStore = documentSessionStore
        self.documentFileWatchStore = documentFileWatchStore
        self.documentTextStore = documentTextStore
        _viewModel = StateObject(
            wrappedValue: DocumentEditorViewModel(sessionStore: documentSessionStore)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            DocumentEditorPanelHeader(
                session: viewModel.session ?? documentSessionStore.session(for: documentID),
                autoSaveStatus: viewModel.autoSaveStatus,
                isFocused: isFocused,
                onSave: saveDocument
            )

            if let errorMessage {
                ContentUnavailableView(
                    "Unable to load document",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                MarkdownEditorRepresentable(
                    text: viewModel.text,
                    selectedRange: viewModel.selectedRange,
                    onTextChange: updateText,
                    onSelectionChange: viewModel.updateSelectedRange
                )
            }

            if let watchErrorMessage {
                DocumentEditorWatchIssueBanner(message: watchErrorMessage)
            }

            DocumentEditorSaveIssueBanner(
                externalChange: viewModel.session?.externalChange,
                hasLocalEdits: viewModel.session?.isDirty == true,
                result: viewModel.lastSaveResult,
                onReload: { allowDiscardingLocalEdits in
                    Task { @MainActor in
                        await reloadExternalDocument(allowDiscardingLocalEdits: allowDiscardingLocalEdits)
                    }
                }
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: documentID) {
            await loadDocument()
        }
        .onDisappear {
            viewModel.cancelAutosave()
            documentFileWatchStore.stopWatching(documentID: documentID)
        }
        .onChange(of: documentFileWatchStore.eventToken(for: documentID)) {
            Task { @MainActor in
                await handleExternalFileWatchEvent()
            }
        }
        .onChange(of: viewModel.autoSaveStatus) {
            guard
                viewModel.autoSaveStatus?.documentID == documentID,
                viewModel.autoSaveStatus?.state == .saved || viewModel.autoSaveStatus?.state == .dirty
            else {
                return
            }

            restartWatchingLoadedDocument()
        }
        .onChange(of: viewModel.session?.textVersion) {
            syncDocumentTextStore()
        }
    }

    private func loadDocument() async {
        do {
            try await viewModel.load(sessionID: documentID)
            syncDocumentTextStore()
            startWatchingLoadedDocument()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateText(_ text: String) {
        viewModel.updateText(text)
        syncDocumentTextStore()
        viewModel.scheduleAutosave()
    }

    private func saveDocument() {
        Task { @MainActor in
            let result = await viewModel.saveNowResult()
            if result.state == .clean || result.state == .dirty {
                restartWatchingLoadedDocument()
            }
        }
    }

    private func handleExternalFileWatchEvent() async {
        guard let watchEvent = documentFileWatchStore.latestEvent(for: documentID) else {
            return
        }

        let didReload = await viewModel.handleExternalFileEvent(watchEvent.event)
        if didReload {
            syncDocumentTextStore()
        }

        if didReload || shouldRestartWatcher(after: watchEvent.event) {
            restartWatchingLoadedDocument()
        }
    }

    private func reloadExternalDocument(allowDiscardingLocalEdits: Bool) async {
        let didReload = await viewModel.reloadExternalChangeFromDisk(
            allowDiscardingLocalEdits: allowDiscardingLocalEdits
        )
        if didReload {
            syncDocumentTextStore()
            restartWatchingLoadedDocument()
        }
    }

    private func startWatchingLoadedDocument() {
        guard let session = viewModel.session else {
            return
        }

        do {
            try documentFileWatchStore.startWatching(session: session)
            watchErrorMessage = nil
        } catch {
            watchErrorMessage = "External change detection is unavailable: \(error.localizedDescription)"
        }
    }

    private func restartWatchingLoadedDocument() {
        guard let session = viewModel.session else {
            return
        }

        do {
            try documentFileWatchStore.restartWatching(session: session)
            watchErrorMessage = nil
        } catch {
            watchErrorMessage = "External change detection is unavailable: \(error.localizedDescription)"
        }
    }

    private func syncDocumentTextStore() {
        documentTextStore.update(
            documentID: documentID,
            text: viewModel.text,
            version: viewModel.session?.textVersion ?? 0
        )
    }

    private func shouldRestartWatcher(after event: FileWatchEvent) -> Bool {
        switch event.kind {
        case .deleted, .renamed:
            return true
        case .contentsChanged, .metadataChanged, .modified:
            return false
        }
    }
}

private struct DocumentEditorPanelHeader: View {
    var session: DocumentSession?
    var autoSaveStatus: AutoSaveStatus?
    var isFocused: Bool
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text(session?.url.lastPathComponent ?? "Editor")
                .lineLimit(1)
            Spacer()
            if let statusText {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            Button(action: onSave) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .foregroundStyle(canSave ? Color.accentColor : Color.secondary)
                    .background(
                        canSave
                            ? Color.accentColor.opacity(0.12)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(canSave ? 0.18 : 0), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut("s", modifiers: [.command])
            .help("Save file")
            .accessibilityLabel("Save file")
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusText: String? {
        if let autoSaveStatus {
            switch autoSaveStatus.state {
            case .scheduled:
                return "Autosave pending"
            case .saving:
                return "Saving"
            case .saved:
                return "Saved"
            case .dirty:
                return "Modified"
            case .failed:
                return "Save failed"
            case .conflicted:
                return "Conflict"
            case .cancelled:
                return session?.isDirty == true ? "Modified" : nil
            case .idle:
                break
            }
        }

        switch session?.saveState {
        case .dirty:
            return "Modified"
        case .saving:
            return "Saving"
        case .failed:
            return "Save failed"
        case .conflicted:
            return "Conflict"
        case .clean, nil:
            return nil
        }
    }

    private var canSave: Bool {
        isFocused && session != nil
    }
}

private struct DocumentEditorSaveIssueBanner: View {
    var externalChange: DocumentExternalChange?
    var hasLocalEdits: Bool
    var result: DocumentSaveResult?
    var onReload: (Bool) -> Void

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .lineLimit(2)
                Spacer()
                if canReload {
                    Button(reloadButtonTitle) {
                        onReload(hasLocalEdits)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var message: String? {
        if result?.state == .failed {
            return result?.failure?.message ?? "The document could not be saved."
        }

        if let externalChange {
            switch externalChange.kind {
            case .modified:
                return "The file changed on disk. Reload before saving again."
            case .deleted:
                return "The file was deleted on disk. Restore it before saving again."
            case .renamed:
                return "The file was moved or renamed on disk. Reopen it from the file tree."
            }
        }

        guard let result else {
            return nil
        }

        switch result.state {
        case .conflicted:
            return "The file changed on disk. Reload before saving again."
        case .clean, .dirty, .saving, .failed:
            return nil
        }
    }

    private var canReload: Bool {
        if externalChange?.kind == .modified {
            return true
        }

        return result?.state == .conflicted && externalChange == nil
    }

    private var reloadButtonTitle: String {
        hasLocalEdits ? "Discard and Reload" : "Reload"
    }
}

private struct DocumentEditorWatchIssueBanner: View {
    var message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct PreviewPanelSurfaceView: View {
    var previewID: PreviewState.ID
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var previewPreferencesStore: PreviewPreferencesStore
    var previewRenderCoordinator: any PreviewRenderingCoordinating
    @ObservedObject var documentTextStore: DocumentTextStore
    @State private var externalLinkMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PreviewPanelHeader(
                session: sourceSession,
                zoom: previewSessionStore.state(for: previewID)?.zoom ?? PreviewState.defaultZoom,
                externalLinkPolicy: previewPreferencesStore.externalLinkPolicy,
                errorMessage: renderErrorMessage,
                externalLinkMessage: externalLinkMessage,
                onZoomOut: { updateZoom(by: -PreviewState.zoomStep) },
                onResetZoom: { previewSessionStore.updateZoom(for: previewID, to: PreviewState.defaultZoom) },
                onZoomIn: { updateZoom(by: PreviewState.zoomStep) },
                onExternalLinkPolicyChange: { previewPreferencesStore.externalLinkPolicy = $0 }
            )
            PreviewWebViewRepresentable(
                state: previewSessionStore.state(for: previewID),
                externalLinkPolicy: previewPreferencesStore.externalLinkPolicy,
                onExternalURLOpenResult: { _, didOpen in
                    externalLinkMessage = didOpen ? nil : "Link open failed"
                }
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: renderToken) {
            await previewRenderCoordinator.render(previewID: previewID)
        }
    }

    private var sourceDocumentID: DocumentSession.ID? {
        previewSessionStore.sourceDocumentID(for: previewID)
    }

    private var sourceSession: DocumentSession? {
        sourceDocumentID.flatMap { documentSessionStore.session(for: $0) }
    }

    private var sourceSnapshot: DocumentTextSnapshot? {
        sourceDocumentID.flatMap { documentTextStore.snapshot(for: $0) }
    }

    private var renderErrorMessage: String? {
        previewSessionStore.state(for: previewID)?.errors.last?.message
    }

    private var renderToken: String {
        let documentPart = sourceDocumentID?.uuidString ?? "missing-document"
        let versionPart = sourceSnapshot?.version ?? sourceSession?.textVersion ?? 0
        let textPart = sourceSnapshot?.text.hashValue ?? 0
        return "\(previewID.uuidString):\(documentPart):\(versionPart):\(textPart)"
    }

    private func updateZoom(by delta: Double) {
        let currentZoom = previewSessionStore.state(for: previewID)?.zoom ?? PreviewState.defaultZoom
        previewSessionStore.updateZoom(for: previewID, to: currentZoom + delta)
    }
}

private struct PreviewPanelHeader: View {
    var session: DocumentSession?
    var zoom: Double
    var externalLinkPolicy: PreviewExternalLinkPolicy
    var errorMessage: String?
    var externalLinkMessage: String?
    var onZoomOut: () -> Void
    var onResetZoom: () -> Void
    var onZoomIn: () -> Void
    var onExternalLinkPolicyChange: (PreviewExternalLinkPolicy) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
            Text(session?.url.lastPathComponent ?? "Preview")
                .lineLimit(1)
            Spacer()
            if errorMessage != nil {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
            if let externalLinkMessage {
                Text(externalLinkMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            externalLinkPolicyMenu
            previewZoomControls
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var previewZoomControls: some View {
        HStack(spacing: 6) {
            Button(action: onZoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(normalizedZoom <= PreviewState.minimumZoom)
            .help("Zoom out preview")
            .accessibilityLabel("Zoom out preview")

            Button(action: onResetZoom) {
                Text(zoomPercentage)
                    .monospacedDigit()
                    .frame(minWidth: 38)
            }
            .buttonStyle(.borderless)
            .disabled(isDefaultZoom)
            .help("Reset preview zoom")
            .accessibilityLabel("Reset preview zoom")

            Button(action: onZoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(normalizedZoom >= PreviewState.maximumZoom)
            .help("Zoom in preview")
            .accessibilityLabel("Zoom in preview")
        }
    }

    private var externalLinkPolicyMenu: some View {
        Menu {
            ForEach(PreviewExternalLinkPolicy.allCases, id: \.self) { policy in
                Button(policy.title) {
                    onExternalLinkPolicyChange(policy)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text(externalLinkPolicy.statusText)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("External link policy")
        .accessibilityLabel("External link policy")
    }

    private var normalizedZoom: Double {
        PreviewState.clampedZoom(zoom)
    }

    private var zoomPercentage: String {
        "\(Int((normalizedZoom * 100).rounded()))%"
    }

    private var isDefaultZoom: Bool {
        abs(normalizedZoom - PreviewState.defaultZoom) < 0.0001
    }
}
