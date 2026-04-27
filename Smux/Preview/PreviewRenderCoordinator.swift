import Foundation

@MainActor
protocol PreviewRenderingCoordinating: AnyObject {
    func render(previewID: PreviewState.ID) async
}

@MainActor
final class PreviewRenderCoordinator: PreviewRenderingCoordinating {
    var documentSessionStore: DocumentSessionStore?
    var previewSessionStore: PreviewSessionStore?
    var sourceResolver: any PreviewRenderSourceResolving

    private let pipeline: MarkdownPreviewPipeline

    init(
        documentSessionStore: DocumentSessionStore? = nil,
        previewSessionStore: PreviewSessionStore? = nil,
        sourceResolver: any PreviewRenderSourceResolving,
        pipeline: MarkdownPreviewPipeline = MarkdownPreviewPipeline()
    ) {
        self.documentSessionStore = documentSessionStore
        self.previewSessionStore = previewSessionStore
        self.sourceResolver = sourceResolver
        self.pipeline = pipeline
    }

    func render(previewID: PreviewState.ID) async {
        guard let previewSessionStore else {
            return
        }

        guard let sourceDocumentID = previewSessionStore.sourceDocumentID(for: previewID) else {
            previewSessionStore.removeState(for: previewID)
            return
        }

        guard let sourceSession = documentSessionStore?.session(for: sourceDocumentID) else {
            previewSessionStore.upsertErrorState(
                previewID: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: 0,
                message: "Preview source document is unavailable."
            )
            return
        }

        do {
            let snapshot = try await sourceResolver.snapshot(for: sourceSession)
            let state = try await pipeline.render(
                documentID: sourceDocumentID,
                text: snapshot.text,
                version: snapshot.version
            )

            guard shouldApply(state, previewID: previewID, store: previewSessionStore) else {
                return
            }

            previewSessionStore.upsertState(state, for: previewID)
        } catch {
            previewSessionStore.upsertErrorState(
                previewID: previewID,
                sourceDocumentID: sourceDocumentID,
                renderVersion: sourceSession.textVersion,
                message: error.localizedDescription
            )
        }
    }

    private func shouldApply(
        _ state: PreviewState,
        previewID: PreviewState.ID,
        store: PreviewSessionStore
    ) -> Bool {
        guard let currentState = store.state(for: previewID) else {
            return true
        }

        return state.renderVersion >= currentState.renderVersion
    }
}
