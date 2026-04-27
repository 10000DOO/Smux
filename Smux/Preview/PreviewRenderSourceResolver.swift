import Foundation

@MainActor
protocol PreviewRenderSourceResolving: AnyObject {
    func snapshot(for session: DocumentSession) async throws -> DocumentTextSnapshot
}

@MainActor
final class PreviewRenderSourceResolver: PreviewRenderSourceResolving {
    var documentTextStore: DocumentTextStore?
    var fileIO: any DocumentFileIO

    init(
        documentTextStore: DocumentTextStore? = nil,
        fileIO: any DocumentFileIO = FileBackedDocumentFileIO()
    ) {
        self.documentTextStore = documentTextStore
        self.fileIO = fileIO
    }

    func snapshot(for session: DocumentSession) async throws -> DocumentTextSnapshot {
        if let snapshot = documentTextStore?.snapshot(for: session.id) {
            return snapshot
        }

        let loadedDocument = try await fileIO.loadText(from: session.url)
        return DocumentTextSnapshot(text: loadedDocument.text, version: session.textVersion)
    }
}
