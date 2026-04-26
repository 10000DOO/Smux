//
//  ContentView.swift
//  Smux
//
//  Created by 이건준 on 4/24/26.
//

import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var appComposition = AppComposition()
    @State private var isWorkspaceImporterPresented = false

    var body: some View {
        WorkspaceShellView(
            workspaceStore: appComposition.workspaceStore,
            panelStore: appComposition.panelStore,
            notificationStore: appComposition.notificationStore,
            recentWorkspaceStore: appComposition.recentWorkspaceStore,
            fileTreeStore: appComposition.fileTreeStore,
            documentSessionStore: appComposition.documentSessionStore,
            documentFileWatchStore: appComposition.documentFileWatchStore,
            previewSessionStore: appComposition.previewSessionStore,
            previewPreferencesStore: appComposition.previewPreferencesStore,
            documentTextStore: appComposition.documentTextStore,
            terminalSessionController: appComposition.terminalSessionController,
            terminalOutputStore: appComposition.terminalOutputStore,
            commandRouter: appComposition.commandRouter
        )
        .toolbar {
            Button {
                appComposition.workspaceStore.clearOpenError()
                isWorkspaceImporterPresented = true
            } label: {
                Label("Open Workspace", systemImage: "folder")
            }
        }
        .fileImporter(
            isPresented: $isWorkspaceImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                await appComposition.openWorkspace(from: result)
            }
        }
    }
}

@MainActor
private final class AppComposition: ObservableObject {
    let workspaceStore: WorkspaceStore
    let panelStore: PanelStore
    let notificationStore: NotificationStore
    let fileTreeStore: FileTreeStore
    let documentSessionStore: DocumentSessionStore
    let documentFileWatchStore: DocumentFileWatchStore
    let previewSessionStore: PreviewSessionStore
    let previewPreferencesStore: PreviewPreferencesStore
    let documentTextStore: DocumentTextStore
    let terminalSessionController: TerminalSessionController
    let terminalOutputStore: TerminalOutputStore
    let agentStateStore: AgentStateStore
    let agentTerminalOutputMonitor: AgentTerminalOutputMonitor
    let recentWorkspaceStore: RecentWorkspaceStore
    let workspaceRepository: any WorkspaceRepository
    let workspaceCoordinator: WorkspaceCoordinator
    let commandRouter: AppCommandRouter
    private let logger = Logger(subsystem: "Smux", category: "AppComposition")

    init() {
        let workspaceStore = WorkspaceStore()
        let panelStore = PanelStore()
        let fileTreeStore = FileTreeStore()
        let systemNotificationDeliverer = UserNotificationCenterNotifier()
        let notificationStore = NotificationStore(systemNotifier: systemNotificationDeliverer)
        let documentSessionStore = DocumentSessionStore()
        let documentFileWatchStore = DocumentFileWatchStore()
        let previewSessionStore = PreviewSessionStore()
        let previewPreferencesStore = PreviewPreferencesStore()
        let documentTextStore = DocumentTextStore()
        let terminalOutputStore = TerminalOutputStore()
        let agentStateStore = AgentStateStore()
        let agentTerminalOutputMonitor = AgentTerminalOutputMonitor(
            stateStore: agentStateStore,
            notificationStore: notificationStore
        )
        let terminalOutputContext = TerminalOutputContext(
            panelStore: panelStore,
            outputStore: terminalOutputStore,
            monitor: agentTerminalOutputMonitor
        )
        let terminalSessionController = TerminalSessionController(
            outputHandler: { [terminalOutputContext] sessionID, data in
                terminalOutputContext.ingest(output: data, sessionID: sessionID)
            }
        )
        terminalOutputContext.terminalSessionController = terminalSessionController
        let recentWorkspaceStore = RecentWorkspaceStore()
        let workspaceRepository = FileBackedWorkspaceRepository()
        let workspaceCoordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: workspaceRepository,
            recentWorkspaceStore: recentWorkspaceStore,
            documentSessionStore: documentSessionStore,
            documentFileWatchStore: documentFileWatchStore,
            documentTextStore: documentTextStore,
            terminalSessionController: terminalSessionController,
            previewSessionStore: previewSessionStore
        )

        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.notificationStore = notificationStore
        self.fileTreeStore = fileTreeStore
        self.documentSessionStore = documentSessionStore
        self.documentFileWatchStore = documentFileWatchStore
        self.previewSessionStore = previewSessionStore
        self.previewPreferencesStore = previewPreferencesStore
        self.documentTextStore = documentTextStore
        self.terminalSessionController = terminalSessionController
        self.terminalOutputStore = terminalOutputStore
        self.agentStateStore = agentStateStore
        self.agentTerminalOutputMonitor = agentTerminalOutputMonitor
        self.recentWorkspaceStore = recentWorkspaceStore
        self.workspaceRepository = workspaceRepository
        self.workspaceCoordinator = workspaceCoordinator
        self.commandRouter = AppCommandRouter(
            workspaceOpening: workspaceCoordinator,
            documentOpening: workspaceCoordinator,
            terminalCommanding: workspaceCoordinator,
            panelCommanding: workspaceCoordinator
        )
        systemNotificationDeliverer.prepare { [logger] result in
            switch result {
            case .success(true):
                break
            case .success(false):
                logger.notice("System notification authorization was not granted.")
            case let .failure(error):
                logger.error("Failed to prepare system notifications: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func openWorkspace(from result: Result<[URL], any Error>) async {
        do {
            guard let rootURL = try result.get().first else {
                workspaceStore.openErrorMessage = "No workspace folder was selected."
                return
            }

            workspaceStore.clearOpenError()
            try await commandRouter.openWorkspace(rootURL: rootURL)
        } catch {
            guard !isUserCancellation(error) else {
                return
            }

            workspaceStore.openErrorMessage = "Failed to open workspace: \(error.localizedDescription)"
        }
    }

    private func isUserCancellation(_ error: any Error) -> Bool {
        guard let cocoaError = error as? CocoaError else {
            return false
        }

        return cocoaError.code == .userCancelled
    }
}

@MainActor
final class PreviewSessionStore: ObservableObject {
    @Published private(set) var states: [PreviewState.ID: PreviewState] = [:]
    @Published private(set) var sourceDocumentIDs: [PreviewState.ID: DocumentSession.ID] = [:]

    func bind(previewID: PreviewState.ID, sourceDocumentID: DocumentSession.ID) {
        sourceDocumentIDs[previewID] = sourceDocumentID
    }

    func sourceDocumentID(for previewID: PreviewState.ID) -> DocumentSession.ID? {
        sourceDocumentIDs[previewID]
    }

    func state(for previewID: PreviewState.ID) -> PreviewState? {
        states[previewID]
    }

    func upsertState(_ state: PreviewState, for previewID: PreviewState.ID) {
        var storedState = state
        storedState.id = previewID
        storedState.zoom = PreviewState.clampedZoom(states[previewID]?.zoom ?? state.zoom)
        states[previewID] = storedState
        sourceDocumentIDs[previewID] = storedState.sourceDocumentID
    }

    func updateZoom(for previewID: PreviewState.ID, to zoom: Double) {
        let clampedZoom = PreviewState.clampedZoom(zoom)

        if var state = states[previewID] {
            state.zoom = clampedZoom
            states[previewID] = state
            return
        }

        guard let sourceDocumentID = sourceDocumentIDs[previewID] else {
            return
        }

        upsertState(
            PreviewState(
                id: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: 0,
                sanitizedMarkdown: nil,
                mermaidBlocks: [],
                errors: [],
                zoom: clampedZoom,
                scrollAnchor: nil
            ),
            for: previewID
        )
    }

    func upsertErrorState(
        previewID: PreviewState.ID,
        sourceDocumentID: DocumentSession.ID,
        renderVersion: Int,
        message: String
    ) {
        upsertState(
            PreviewState(
                id: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: renderVersion,
                sanitizedMarkdown: nil,
                mermaidBlocks: [],
                errors: [
                    PreviewRenderError(
                        id: UUID(),
                        message: message,
                        sourceRange: nil
                    )
                ],
                zoom: PreviewState.defaultZoom,
                scrollAnchor: nil
            ),
            for: previewID
        )
    }

    func removeState(for previewID: PreviewState.ID) {
        states.removeValue(forKey: previewID)
    }

    func replaceStates(_ restoredStates: [PreviewState]) {
        let normalizedStates = restoredStates.map { state in
            var normalizedState = state
            normalizedState.zoom = PreviewState.clampedZoom(state.zoom)
            return normalizedState
        }

        states = Dictionary(uniqueKeysWithValues: normalizedStates.map { ($0.id, $0) })
        sourceDocumentIDs = Dictionary(uniqueKeysWithValues: normalizedStates.map { ($0.id, $0.sourceDocumentID) })
    }

    func snapshotStates() -> [PreviewState] {
        var snapshotStates = states

        for (previewID, sourceDocumentID) in sourceDocumentIDs where snapshotStates[previewID] == nil {
            snapshotStates[previewID] = PreviewState(
                id: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: 0,
                sanitizedMarkdown: nil,
                mermaidBlocks: [],
                errors: [],
                zoom: PreviewState.defaultZoom,
                scrollAnchor: nil
            )
        }

        return Array(snapshotStates.values)
    }
}

nonisolated struct DocumentTextSnapshot: Equatable {
    var text: String
    var version: Int
}

@MainActor
final class DocumentTextStore: ObservableObject {
    @Published private(set) var snapshots: [DocumentSession.ID: DocumentTextSnapshot] = [:]

    func snapshot(for documentID: DocumentSession.ID) -> DocumentTextSnapshot? {
        snapshots[documentID]
    }

    func update(documentID: DocumentSession.ID, text: String, version: Int) {
        snapshots[documentID] = DocumentTextSnapshot(text: text, version: version)
    }

    func clearAll() {
        snapshots.removeAll()
    }
}

@MainActor
private final class TerminalOutputContext {
    weak var terminalSessionController: TerminalSessionController?

    private weak var panelStore: PanelStore?
    private let outputStore: TerminalOutputStore
    private let monitor: AgentTerminalOutputMonitor

    init(
        panelStore: PanelStore,
        outputStore: TerminalOutputStore,
        monitor: AgentTerminalOutputMonitor
    ) {
        self.panelStore = panelStore
        self.outputStore = outputStore
        self.monitor = monitor
    }

    func ingest(output data: Data, sessionID: TerminalSession.ID) {
        guard let session = terminalSessionController?.session(for: sessionID) else {
            return
        }

        outputStore.append(data, for: sessionID)
        monitor.ingest(
            output: data,
            sessionID: sessionID,
            workspaceID: session.workspaceID,
            panelID: panelStore?.rootNode.panelID(containingTerminalSession: sessionID)
        )
    }
}

private extension PanelNode {
    func panelID(containingTerminalSession sessionID: TerminalSession.ID) -> PanelNode.ID? {
        if case let .terminal(storedSessionID) = surface, storedSessionID == sessionID, isLeaf {
            return id
        }

        return children.lazy.compactMap {
            $0.panelID(containingTerminalSession: sessionID)
        }.first
    }
}

#Preview {
    ContentView()
}
