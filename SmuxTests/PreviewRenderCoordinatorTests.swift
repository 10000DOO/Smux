import XCTest
@testable import Smux

@MainActor
final class PreviewRenderCoordinatorTests: XCTestCase {
    func testRenderUsesLiveDocumentTextSnapshotBeforeDiskFallback() async throws {
        let documentID = DocumentSession.ID()
        let previewID = PreviewState.ID()
        let documentStore = DocumentSessionStore()
        let previewStore = PreviewSessionStore()
        let textStore = DocumentTextStore()
        let fileIO = StubPreviewDocumentFileIO(text: "# Disk")
        let coordinator = PreviewRenderCoordinator(
            documentSessionStore: documentStore,
            previewSessionStore: previewStore,
            sourceResolver: PreviewRenderSourceResolver(documentTextStore: textStore, fileIO: fileIO)
        )

        documentStore.upsertSession(
            DocumentSession.make(
                id: documentID,
                workspaceID: Workspace.ID(),
                url: URL(fileURLWithPath: "/tmp/preview.md"),
                textVersion: 2
            )
        )
        previewStore.bind(previewID: previewID, sourceDocumentID: documentID)
        textStore.update(documentID: documentID, text: "# Live", version: 3)

        await coordinator.render(previewID: previewID)

        let state = try XCTUnwrap(previewStore.state(for: previewID))
        XCTAssertEqual(state.renderVersion, 3)
        XCTAssertTrue(state.sanitizedMarkdown?.html.contains("Live") == true)
        XCTAssertEqual(fileIO.loadCount, 0)
    }

    func testRenderFallsBackToDiskWhenNoLiveSnapshotExists() async throws {
        let documentID = DocumentSession.ID()
        let previewID = PreviewState.ID()
        let documentStore = DocumentSessionStore()
        let previewStore = PreviewSessionStore()
        let fileIO = StubPreviewDocumentFileIO(text: "## Disk")
        let coordinator = PreviewRenderCoordinator(
            documentSessionStore: documentStore,
            previewSessionStore: previewStore,
            sourceResolver: PreviewRenderSourceResolver(fileIO: fileIO)
        )

        documentStore.upsertSession(
            DocumentSession.make(
                id: documentID,
                workspaceID: Workspace.ID(),
                url: URL(fileURLWithPath: "/tmp/preview.md"),
                textVersion: 7
            )
        )
        previewStore.bind(previewID: previewID, sourceDocumentID: documentID)

        await coordinator.render(previewID: previewID)

        let state = try XCTUnwrap(previewStore.state(for: previewID))
        XCTAssertEqual(state.renderVersion, 7)
        XCTAssertTrue(state.sanitizedMarkdown?.html.contains("Disk") == true)
        XCTAssertEqual(fileIO.loadCount, 1)
    }

    func testRenderStoresErrorWhenSourceDocumentIsMissing() async throws {
        let documentID = DocumentSession.ID()
        let previewID = PreviewState.ID()
        let previewStore = PreviewSessionStore()
        let coordinator = PreviewRenderCoordinator(
            documentSessionStore: DocumentSessionStore(),
            previewSessionStore: previewStore,
            sourceResolver: PreviewRenderSourceResolver(fileIO: StubPreviewDocumentFileIO(text: ""))
        )
        previewStore.bind(previewID: previewID, sourceDocumentID: documentID)

        await coordinator.render(previewID: previewID)

        let state = try XCTUnwrap(previewStore.state(for: previewID))
        XCTAssertNil(state.sanitizedMarkdown)
        XCTAssertEqual(state.renderVersion, 0)
        XCTAssertTrue(state.errors.contains { $0.message.contains("Preview source document is unavailable") })
    }

    func testRenderDoesNotOverwriteNewerPreviewStateWithOlderVersion() async throws {
        let documentID = DocumentSession.ID()
        let previewID = PreviewState.ID()
        let documentStore = DocumentSessionStore()
        let previewStore = PreviewSessionStore()
        let coordinator = PreviewRenderCoordinator(
            documentSessionStore: documentStore,
            previewSessionStore: previewStore,
            sourceResolver: PreviewRenderSourceResolver(fileIO: StubPreviewDocumentFileIO(text: "# Older"))
        )
        let currentState = PreviewState(
            id: previewID,
            sourceDocumentID: documentID,
            renderVersion: 10,
            sanitizedMarkdown: SanitizedMarkdown(html: "<p>Current</p>"),
            mermaidBlocks: [],
            errors: [],
            zoom: 1.4,
            scrollAnchor: nil
        )

        documentStore.upsertSession(
            DocumentSession.make(
                id: documentID,
                workspaceID: Workspace.ID(),
                url: URL(fileURLWithPath: "/tmp/preview.md"),
                textVersion: 2
            )
        )
        previewStore.upsertState(currentState, for: previewID)

        await coordinator.render(previewID: previewID)

        let state = try XCTUnwrap(previewStore.state(for: previewID))
        XCTAssertEqual(state.renderVersion, 10)
        XCTAssertEqual(state.sanitizedMarkdown?.html, "<p>Current</p>")
        XCTAssertEqual(state.zoom, 1.4)
    }
}

private final class StubPreviewDocumentFileIO: DocumentFileIO, @unchecked Sendable {
    let text: String
    private(set) var loadCount = 0

    init(text: String) {
        self.text = text
    }

    func loadText(from url: URL) async throws -> LoadedDocument {
        loadCount += 1
        return LoadedDocument(
            text: text,
            fingerprint: FileFingerprint(
                modificationDate: Date(timeIntervalSince1970: 1),
                size: Int64(text.utf8.count),
                contentHash: "\(text.hashValue)"
            )
        )
    }

    func saveText(
        _ text: String,
        to url: URL,
        replacing expectedFingerprint: FileFingerprint?
    ) async throws -> FileFingerprint {
        FileFingerprint()
    }

    func fingerprint(for url: URL) async throws -> FileFingerprint {
        FileFingerprint()
    }

    func fileExists(at url: URL) -> Bool {
        true
    }
}
