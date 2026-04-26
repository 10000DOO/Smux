import SwiftUI

struct SplitPanelView: View {
    var node: PanelNode
    var focusedPanelID: PanelNode.ID?
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var documentFileWatchStore: DocumentFileWatchStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var previewPreferencesStore: PreviewPreferencesStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @ObservedObject var terminalSessionController: TerminalSessionController
    @ObservedObject var terminalOutputStore: TerminalOutputStore
    var notifications: [WorkspaceNotification] = []
    var onFocus: (PanelNode.ID) -> Void
    var onReplaceSurface: (PanelNode.ID, PanelSurfaceDescriptor) -> Void
    var onSplit: (PanelNode.ID, SplitDirection) -> Void
    var onCreateTerminal: (PanelNode.ID) -> Void
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
            documentSessionStore: documentSessionStore,
            documentFileWatchStore: documentFileWatchStore,
            previewSessionStore: previewSessionStore,
            previewPreferencesStore: previewPreferencesStore,
            documentTextStore: documentTextStore,
            terminalSessionController: terminalSessionController,
            terminalOutputStore: terminalOutputStore,
            notifications: notifications,
            onFocus: onFocus,
            onReplaceSurface: onReplaceSurface,
            onSplit: onSplit,
            onCreateTerminal: onCreateTerminal,
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

                onUpdateSplitRatio(node.id, PanelNode.clampedRatio(newRatio))
            }
            .onEnded { _ in
                dragStartRatio = nil
            }
    }

    @ViewBuilder
    private func surfaceView(_ surface: PanelSurfaceDescriptor, panelID: PanelNode.ID) -> some View {
        Group {
            switch surface {
            case .terminal(let sessionID):
                TerminalPanelSurfaceView(
                    sessionID: sessionID,
                    terminalSessionController: terminalSessionController,
                    terminalOutputStore: terminalOutputStore
                )
            case .editor(let documentID):
                DocumentEditorPanelSurfaceView(
                    documentID: documentID,
                    isFocused: focusedPanelID == panelID,
                    documentSessionStore: documentSessionStore,
                    documentFileWatchStore: documentFileWatchStore,
                    documentTextStore: documentTextStore
                )
                .id(documentID)
            case .preview(let previewID):
                PreviewPanelSurfaceView(
                    previewID: previewID,
                    documentSessionStore: documentSessionStore,
                    previewSessionStore: previewSessionStore,
                    previewPreferencesStore: previewPreferencesStore,
                    documentTextStore: documentTextStore
                )
            case .empty:
                PanelSurfacePlaceholderView(
                    surface: surface,
                    isFocused: focusedPanelID == panelID,
                    onReplaceSurface: { replacement in
                        onReplaceSurface(panelID, replacement)
                    },
                    onSplit: { direction in
                        onSplit(panelID, direction)
                    },
                    onCreateTerminal: {
                        onCreateTerminal(panelID)
                    }
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(focusedPanelID == panelID ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            PanelNotificationBadgeView(
                count: PanelNotificationBadgeSummary.unacknowledgedBadgeCount(
                    for: panelID,
                    notifications: notifications
                )
            )
            .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus(panelID)
        }
    }
}

private struct SplitPanelDivider: View {
    static let length: CGFloat = 6

    var direction: SplitDirection

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.8))
            .contentShape(Rectangle())
            .accessibilityLabel(direction == .horizontal ? "Resize columns" : "Resize rows")
            .accessibilityHint("Drag to resize adjacent panels")
    }
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
    @StateObject private var viewModel: TerminalViewModel

    init(
        sessionID: TerminalSession.ID,
        terminalSessionController: TerminalSessionController,
        terminalOutputStore: TerminalOutputStore
    ) {
        self.sessionID = sessionID
        self.terminalSessionController = terminalSessionController
        self.terminalOutputStore = terminalOutputStore
        _viewModel = StateObject(
            wrappedValue: TerminalViewModel(
                session: terminalSessionController.session(for: sessionID),
                terminalCore: terminalSessionController
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalPanelHeader(session: session)

            GeometryReader { proxy in
                TerminalViewRepresentable(
                    buffer: terminalOutputStore.output(for: sessionID),
                    styledRuns: terminalOutputStore.styledOutput(for: sessionID),
                    onInput: viewModel.sendInput
                )
                .onAppear {
                    resizeTerminal(to: proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    resizeTerminal(to: newSize)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            syncSession()
        }
        .onChange(of: terminalSessionController.sessions[sessionID]) {
            syncSession()
        }
    }

    private var session: TerminalSession? {
        terminalSessionController.sessions[sessionID]
    }

    private func syncSession() {
        viewModel.session = session
    }

    private func resizeTerminal(to size: CGSize) {
        let gridSize = TerminalGridSizeEstimator.estimate(size: size)
        viewModel.resize(columns: gridSize.columns, rows: gridSize.rows)
    }
}

private struct TerminalPanelHeader: View {
    var session: TerminalSession?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
            Text(session?.title ?? "Terminal")
                .lineLimit(1)
            Spacer()
            Text(session?.status.rawValue.capitalized ?? "Missing")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
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
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(!isFocused || session == nil)
            .keyboardShortcut("s", modifiers: [.command])
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
    @ObservedObject var documentTextStore: DocumentTextStore
    @State private var errorMessage: String?
    @State private var externalLinkMessage: String?
    @State private var pipeline = MarkdownPreviewPipeline()
    @State private var fileIO = FileBackedDocumentFileIO()

    var body: some View {
        VStack(spacing: 0) {
            PreviewPanelHeader(
                session: sourceSession,
                zoom: previewSessionStore.state(for: previewID)?.zoom ?? PreviewState.defaultZoom,
                externalLinkPolicy: previewPreferencesStore.externalLinkPolicy,
                errorMessage: errorMessage,
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
            await renderPreview()
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

    private var renderToken: String {
        let documentPart = sourceDocumentID?.uuidString ?? "missing-document"
        let versionPart = sourceSnapshot?.version ?? sourceSession?.textVersion ?? 0
        let textPart = sourceSnapshot?.text.hashValue ?? 0
        return "\(previewID.uuidString):\(documentPart):\(versionPart):\(textPart)"
    }

    private func renderPreview() async {
        guard let sourceDocumentID else {
            errorMessage = "Preview source document is unavailable."
            previewSessionStore.removeState(for: previewID)
            return
        }

        guard let sourceSession else {
            let message = "Preview source document is unavailable."
            errorMessage = message
            previewSessionStore.upsertErrorState(
                previewID: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: 0,
                message: message
            )
            return
        }

        do {
            let snapshot = try await currentTextSnapshot(for: sourceSession)
            let state = try await pipeline.render(
                documentID: sourceDocumentID,
                text: snapshot.text,
                version: snapshot.version
            )
            previewSessionStore.upsertState(state, for: previewID)
            errorMessage = nil
        } catch {
            let message = error.localizedDescription
            let version = sourceSnapshot?.version ?? sourceSession.textVersion
            errorMessage = message
            previewSessionStore.upsertErrorState(
                previewID: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: version,
                message: message
            )
        }
    }

    private func currentTextSnapshot(for session: DocumentSession) async throws -> DocumentTextSnapshot {
        if let sourceSnapshot {
            return sourceSnapshot
        }

        let loadedDocument = try await fileIO.loadText(from: session.url)
        return DocumentTextSnapshot(text: loadedDocument.text, version: session.textVersion)
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
