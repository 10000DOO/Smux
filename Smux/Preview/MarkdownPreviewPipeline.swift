import Foundation

final class MarkdownPreviewPipeline {
    func render(documentID: DocumentSession.ID, text: String, version: Int) async throws -> PreviewState {
        fatalError("TODO")
    }

    func invalidate(documentID: DocumentSession.ID) {}
}
