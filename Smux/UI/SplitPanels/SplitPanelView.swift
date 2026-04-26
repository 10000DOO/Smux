import SwiftUI

struct SplitPanelView: View {
    var node: PanelNode
    var focusedPanelID: PanelNode.ID?
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @ObservedObject var terminalSessionController: TerminalSessionController
    @ObservedObject var terminalOutputStore: TerminalOutputStore
    var notifications: [WorkspaceNotification] = []
    var onFocus: (PanelNode.ID) -> Void
    var onReplaceSurface: (PanelNode.ID, PanelSurfaceDescriptor) -> Void
    var onSplit: (PanelNode.ID, SplitDirection) -> Void
    var onCreateTerminal: (PanelNode.ID) -> Void

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
        switch node.direction {
        case .horizontal:
            HStack(spacing: 1) {
                ForEach(node.children) { child in
                    SplitPanelView(
                        node: child,
                        focusedPanelID: focusedPanelID,
                        documentSessionStore: documentSessionStore,
                        previewSessionStore: previewSessionStore,
                        documentTextStore: documentTextStore,
                        terminalSessionController: terminalSessionController,
                        terminalOutputStore: terminalOutputStore,
                        notifications: notifications,
                        onFocus: onFocus,
                        onReplaceSurface: onReplaceSurface,
                        onSplit: onSplit,
                        onCreateTerminal: onCreateTerminal
                    )
                }
            }
        case .vertical:
            VStack(spacing: 1) {
                ForEach(node.children) { child in
                    SplitPanelView(
                        node: child,
                        focusedPanelID: focusedPanelID,
                        documentSessionStore: documentSessionStore,
                        previewSessionStore: previewSessionStore,
                        documentTextStore: documentTextStore,
                        terminalSessionController: terminalSessionController,
                        terminalOutputStore: terminalOutputStore,
                        notifications: notifications,
                        onFocus: onFocus,
                        onReplaceSurface: onReplaceSurface,
                        onSplit: onSplit,
                        onCreateTerminal: onCreateTerminal
                    )
                }
            }
        case nil:
            surfaceView(.empty, panelID: node.id)
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
                    documentSessionStore: documentSessionStore,
                    documentTextStore: documentTextStore
                )
            case .preview(let previewID):
                PreviewPanelSurfaceView(
                    previewID: previewID,
                    documentSessionStore: documentSessionStore,
                    previewSessionStore: previewSessionStore,
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
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @StateObject private var viewModel: DocumentEditorViewModel
    @State private var errorMessage: String?

    init(
        documentID: DocumentSession.ID,
        documentSessionStore: DocumentSessionStore,
        documentTextStore: DocumentTextStore
    ) {
        self.documentID = documentID
        self.documentSessionStore = documentSessionStore
        self.documentTextStore = documentTextStore
        _viewModel = StateObject(
            wrappedValue: DocumentEditorViewModel(sessionStore: documentSessionStore)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            DocumentEditorPanelHeader(session: viewModel.session ?? documentSessionStore.session(for: documentID))

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
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: documentID) {
            await loadDocument()
        }
    }

    private func loadDocument() async {
        do {
            try await viewModel.load(sessionID: documentID)
            documentTextStore.update(
                documentID: documentID,
                text: viewModel.text,
                version: viewModel.session?.textVersion ?? 0
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateText(_ text: String) {
        viewModel.updateText(text)
        documentTextStore.update(
            documentID: documentID,
            text: viewModel.text,
            version: viewModel.session?.textVersion ?? 0
        )
    }
}

private struct DocumentEditorPanelHeader: View {
    var session: DocumentSession?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text(session?.url.lastPathComponent ?? "Editor")
                .lineLimit(1)
            Spacer()
            if session?.isDirty == true {
                Text("Modified")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PreviewPanelSurfaceView: View {
    var previewID: PreviewState.ID
    @ObservedObject var documentSessionStore: DocumentSessionStore
    @ObservedObject var previewSessionStore: PreviewSessionStore
    @ObservedObject var documentTextStore: DocumentTextStore
    @State private var errorMessage: String?

    private let pipeline = MarkdownPreviewPipeline()
    private let fileIO = FileBackedDocumentFileIO()

    var body: some View {
        VStack(spacing: 0) {
            PreviewPanelHeader(session: sourceSession, errorMessage: errorMessage)
            PreviewWebViewRepresentable(state: previewSessionStore.state(for: previewID))
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
}

private struct PreviewPanelHeader: View {
    var session: DocumentSession?
    var errorMessage: String?

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
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
