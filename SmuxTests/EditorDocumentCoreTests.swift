import XCTest
@testable import Smux

final class EditorDocumentCoreTests: XCTestCase {
    func testDocumentLanguageDetectionCoversSupportedExtensionsAndPlainText() {
        XCTAssertEqual(DocumentLanguage.detect(for: URL(fileURLWithPath: "/tmp/README.md")), .markdown)
        XCTAssertEqual(DocumentLanguage.detect(for: URL(fileURLWithPath: "/tmp/README.markdown")), .markdown)
        XCTAssertEqual(DocumentLanguage.detect(for: URL(fileURLWithPath: "/tmp/diagram.mmd")), .mermaid)
        XCTAssertEqual(DocumentLanguage.detect(for: URL(fileURLWithPath: "/tmp/diagram.mermaid")), .mermaid)
        XCTAssertEqual(DocumentLanguage.detect(for: URL(fileURLWithPath: "/tmp/NOTES.MD")), .markdown)
        XCTAssertEqual(DocumentLanguage.detect(for: URL(fileURLWithPath: "/tmp/plain.txt")), .plainText)
    }

    @MainActor
    func testLoadSessionReadsTextAndResetsCleanState() async throws {
        let fingerprint = makeFingerprint(size: 7, contentHash: "loaded")
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Loaded.md"),
            textVersion: 3,
            isDirty: true,
            saveState: .dirty
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "# Title", fingerprint: fingerprint)
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        store.upsertSession(session)
        try await viewModel.load(sessionID: session.id)

        XCTAssertEqual(viewModel.text, "# Title")
        XCTAssertEqual(viewModel.session?.id, session.id)
        XCTAssertEqual(viewModel.session?.language, .markdown)
        XCTAssertEqual(viewModel.session?.textVersion, 3)
        XCTAssertEqual(viewModel.session?.fileFingerprint, fingerprint)
        XCTAssertEqual(viewModel.session?.isDirty, false)
        XCTAssertEqual(viewModel.session?.saveState, .clean)
        XCTAssertNil(viewModel.session?.conflict)
        XCTAssertEqual(viewModel.selectedRange?.location, 0)
        XCTAssertEqual(viewModel.selectedRange?.length, 0)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testUpdateTextMarksSessionDirtyAndPreservesSelection() async throws {
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Editable.mermaid")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "graph LR", fingerprint: makeFingerprint())
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateSelectedRange(NSRange(location: 2, length: 4))
        viewModel.updateText("graph TD")

        XCTAssertEqual(viewModel.text, "graph TD")
        XCTAssertEqual(viewModel.session?.language, .mermaid)
        XCTAssertEqual(viewModel.session?.textVersion, 1)
        XCTAssertEqual(viewModel.session?.isDirty, true)
        XCTAssertEqual(viewModel.session?.saveState, .dirty)
        XCTAssertEqual(viewModel.selectedRange?.location, 2)
        XCTAssertEqual(viewModel.selectedRange?.length, 4)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)

        viewModel.updateText("graph TD")

        XCTAssertEqual(viewModel.session?.textVersion, 1)
    }

    @MainActor
    func testSaveNowWritesTextAndMarksSessionClean() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("Draft.md", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try Data("Initial".utf8).write(to: fileURL)

        let store = DocumentSessionStore()
        let viewModel = DocumentEditorViewModel(
            sessionStore: store,
            fileIO: FileBackedDocumentFileIO()
        )
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: fileURL
        )

        try await viewModel.load(session: session)
        viewModel.updateText("Saved body")
        try await viewModel.saveNow()

        let savedText = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(savedText, "Saved body")
        XCTAssertEqual(viewModel.session?.isDirty, false)
        XCTAssertEqual(viewModel.session?.saveState, .clean)
        XCTAssertEqual(viewModel.session?.textVersion, 1)
        XCTAssertEqual(viewModel.session?.fileFingerprint?.size, Int64(Data("Saved body".utf8).count))
        XCTAssertNotNil(viewModel.session?.fileFingerprint?.contentHash)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testSaveNowDetectsExternalDiskChangesBeforeWriting() async throws {
        let loadedFingerprint = makeFingerprint(size: 6, contentHash: "loaded")
        let diskFingerprint = makeFingerprint(size: 12, contentHash: "external")
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Conflicted.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: loadedFingerprint),
            fingerprintResult: diskFingerprint
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("After")

        do {
            try await viewModel.saveNow()
            XCTFail("Expected saveNow to throw.")
        } catch let error as DocumentEditorError {
            guard case let .conflicted(conflict) = error else {
                XCTFail("Expected conflict error.")
                return
            }
            XCTAssertEqual(conflict.loadedFingerprint, loadedFingerprint)
            XCTAssertEqual(conflict.currentFingerprint, diskFingerprint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(fileIO.savedText)
        XCTAssertEqual(viewModel.session?.saveState, .conflicted)
        XCTAssertEqual(viewModel.session?.isDirty, true)
        XCTAssertEqual(viewModel.session?.conflict?.loadedFingerprint, loadedFingerprint)
        XCTAssertEqual(viewModel.session?.conflict?.currentFingerprint, diskFingerprint)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testSaveNowKeepsDirtyWhenTextChangesDuringSave() async throws {
        let loadedFingerprint = makeFingerprint(size: 6, contentHash: "loaded")
        let savedFingerprint = makeFingerprint(size: 5, contentHash: "saved")
        let saveGate = SaveGate()
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Reentrant.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: loadedFingerprint),
            savedFingerprint: savedFingerprint,
            saveGate: saveGate
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("First")

        let saveTask = Task { @MainActor in
            try await viewModel.saveNow()
        }
        await saveGate.waitUntilWaiting()

        viewModel.updateText("Second")
        await saveGate.resume()
        try await saveTask.value

        XCTAssertEqual(fileIO.savedText, "First")
        XCTAssertEqual(viewModel.text, "Second")
        XCTAssertEqual(viewModel.session?.textVersion, 2)
        XCTAssertEqual(viewModel.session?.fileFingerprint, savedFingerprint)
        XCTAssertEqual(viewModel.session?.isDirty, true)
        XCTAssertEqual(viewModel.session?.saveState, .dirty)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testSaveNowRejectsConcurrentSave() async throws {
        let saveGate = SaveGate()
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Concurrent.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: makeFingerprint()),
            saveGate: saveGate
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("After")

        let saveTask = Task { @MainActor in
            try await viewModel.saveNow()
        }
        await saveGate.waitUntilWaiting()

        do {
            try await viewModel.saveNow()
            XCTFail("Expected concurrent save to throw.")
        } catch let error as DocumentEditorError {
            XCTAssertEqual(error, .saveAlreadyInProgress)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await saveGate.resume()
        try await saveTask.value
    }

    @MainActor
    func testSaveNowFailureMarksSessionFailedAndKeepsDirtyText() async throws {
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Unsaved.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: makeFingerprint()),
            saveError: EditorDocumentCoreTestError.saveFailed
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("After")

        do {
            try await viewModel.saveNow()
            XCTFail("Expected saveNow to throw.")
        } catch let error as EditorDocumentCoreTestError {
            XCTAssertEqual(error, .saveFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(viewModel.text, "After")
        XCTAssertEqual(viewModel.session?.isDirty, true)
        XCTAssertEqual(viewModel.session?.saveState, .failed)
        XCTAssertEqual(viewModel.session?.textVersion, 1)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    private func makeFingerprint(
        size: Int64 = 6,
        contentHash: String = "fingerprint"
    ) -> FileFingerprint {
        FileFingerprint(
            modificationDate: Date(timeIntervalSince1970: 1),
            size: size,
            contentHash: contentHash
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SmuxEditorTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return directoryURL
    }
}

private final class StubDocumentFileIO: DocumentFileIO, @unchecked Sendable {
    var loadedDocument: LoadedDocument
    var savedFingerprint: FileFingerprint
    var fingerprintResult: FileFingerprint?
    var saveError: (any Error)?
    var saveGate: SaveGate?
    private(set) var savedText: String?
    private(set) var savedURL: URL?

    init(
        loadedDocument: LoadedDocument,
        savedFingerprint: FileFingerprint = FileFingerprint(
            modificationDate: Date(timeIntervalSince1970: 2),
            size: 10,
            contentHash: "saved"
        ),
        fingerprintResult: FileFingerprint? = nil,
        saveGate: SaveGate? = nil,
        saveError: (any Error)? = nil
    ) {
        self.loadedDocument = loadedDocument
        self.savedFingerprint = savedFingerprint
        self.fingerprintResult = fingerprintResult
        self.saveGate = saveGate
        self.saveError = saveError
    }

    func loadText(from url: URL) async throws -> LoadedDocument {
        loadedDocument
    }

    func saveText(_ text: String, to url: URL) async throws -> FileFingerprint {
        if let saveError {
            throw saveError
        }

        if let saveGate {
            await saveGate.wait()
        }

        savedText = text
        savedURL = url
        return savedFingerprint
    }

    func fingerprint(for url: URL) async throws -> FileFingerprint {
        fingerprintResult ?? loadedDocument.fingerprint
    }
}

private actor SaveGate {
    private var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilWaiting() async {
        while !isWaiting {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum EditorDocumentCoreTestError: Error, Equatable {
    case saveFailed
}
