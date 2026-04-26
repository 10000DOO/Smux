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
        XCTAssertEqual(viewModel.lastSaveResult?.state, .clean)
        XCTAssertNil(viewModel.lastSaveResult?.failure)
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
        XCTAssertEqual(viewModel.lastSaveResult?.state, .conflicted)
        XCTAssertEqual(viewModel.lastSaveResult?.conflict?.loadedFingerprint, loadedFingerprint)
        XCTAssertNil(viewModel.lastSaveResult?.failure)
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
        XCTAssertEqual(viewModel.lastSaveResult?.state, .dirty)
        XCTAssertNil(viewModel.lastSaveResult?.failure)
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
        XCTAssertEqual(viewModel.lastSaveResult?.state, .failed)
        XCTAssertEqual(viewModel.lastSaveResult?.failure?.kind, .fileIO)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testSaveNowResultReturnsFailureWithoutThrowing() async throws {
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/ResultFailure.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: makeFingerprint()),
            saveError: EditorDocumentCoreTestError.saveFailed
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("After")
        let result = await viewModel.saveNowResult()

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.failure?.kind, .fileIO)
        XCTAssertEqual(viewModel.lastSaveResult, result)
        XCTAssertEqual(viewModel.session?.saveState, .failed)
    }

    @MainActor
    func testViewModelSchedulesAutosaveAndPublishesCompletedStatus() async throws {
        let loadedFingerprint = makeFingerprint(size: 6, contentHash: "loaded")
        let savedFingerprint = makeFingerprint(size: 5, contentHash: "saved")
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/Autosave.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: loadedFingerprint),
            savedFingerprint: savedFingerprint
        )
        let viewModel = DocumentEditorViewModel(
            sessionStore: store,
            fileIO: fileIO,
            autoSaveDebounceInterval: 0.01
        )

        try await viewModel.load(session: session)
        viewModel.updateText("After")
        let scheduledStatus = viewModel.scheduleAutosave()

        XCTAssertEqual(scheduledStatus?.state, .scheduled)
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .scheduled)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fileIO.saveAttemptCount, 1)
        XCTAssertEqual(fileIO.savedText, "After")
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .saved)
        XCTAssertEqual(viewModel.autoSaveStatus?.result?.state, .clean)
        XCTAssertEqual(viewModel.lastSaveResult?.state, .clean)
        XCTAssertEqual(viewModel.session?.saveState, .clean)
        XCTAssertEqual(viewModel.session?.isDirty, false)
        XCTAssertEqual(viewModel.session?.fileFingerprint, savedFingerprint)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testFlushAutosavePropagatesConflictToObservableState() async throws {
        let loadedFingerprint = makeFingerprint(size: 6, contentHash: "loaded")
        let diskFingerprint = makeFingerprint(size: 12, contentHash: "external")
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/AutosaveConflict.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: loadedFingerprint),
            fingerprintResult: diskFingerprint
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("After")
        viewModel.scheduleAutosave()
        let result = await viewModel.flushAutosave()

        XCTAssertEqual(result.state, .conflicted)
        XCTAssertEqual(result.conflict?.loadedFingerprint, loadedFingerprint)
        XCTAssertEqual(result.conflict?.currentFingerprint, diskFingerprint)
        XCTAssertNil(fileIO.savedText)
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .conflicted)
        XCTAssertEqual(viewModel.autoSaveStatus?.conflict, result.conflict)
        XCTAssertEqual(viewModel.lastSaveResult, result)
        XCTAssertEqual(viewModel.session?.saveState, .conflicted)
        XCTAssertEqual(viewModel.session?.conflict, result.conflict)
        XCTAssertEqual(viewModel.session?.isDirty, true)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testFlushAutosavePropagatesFailureToObservableState() async throws {
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/AutosaveFailure.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: makeFingerprint()),
            saveError: EditorDocumentCoreTestError.saveFailed
        )
        let viewModel = DocumentEditorViewModel(sessionStore: store, fileIO: fileIO)

        try await viewModel.load(session: session)
        viewModel.updateText("After")
        viewModel.scheduleAutosave()
        let result = await viewModel.flushAutosave()

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.failure?.kind, .fileIO)
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .failed)
        XCTAssertEqual(viewModel.autoSaveStatus?.failure, result.failure)
        XCTAssertEqual(viewModel.lastSaveResult, result)
        XCTAssertEqual(viewModel.session?.saveState, .failed)
        XCTAssertEqual(viewModel.session?.isDirty, true)
        XCTAssertEqual(store.session(for: session.id), viewModel.session)
    }

    @MainActor
    func testSaveNowResultCancelsPendingAutosaveWithoutDuplicateWrite() async throws {
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/ExplicitCancelsAutosave.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: makeFingerprint())
        )
        let viewModel = DocumentEditorViewModel(
            sessionStore: store,
            fileIO: fileIO,
            autoSaveDebounceInterval: 0.05
        )

        try await viewModel.load(session: session)
        viewModel.updateText("After")
        viewModel.scheduleAutosave()
        let result = await viewModel.saveNowResult()
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(result.state, .clean)
        XCTAssertEqual(fileIO.saveAttemptCount, 1)
        XCTAssertEqual(fileIO.savedText, "After")
        XCTAssertEqual(viewModel.lastSaveResult, result)
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .idle)
        XCTAssertEqual(viewModel.session?.saveState, .clean)
    }

    @MainActor
    func testSaveNowResultDuringAutosaveUsesSavingGuardWithoutDuplicateWrite() async throws {
        let saveGate = SaveGate()
        let session = DocumentSession.make(
            workspaceID: Workspace.ID(),
            url: URL(fileURLWithPath: "/tmp/ExplicitDuringAutosave.md")
        )
        let store = DocumentSessionStore()
        let fileIO = StubDocumentFileIO(
            loadedDocument: LoadedDocument(text: "Before", fingerprint: makeFingerprint()),
            saveGate: saveGate
        )
        let viewModel = DocumentEditorViewModel(
            sessionStore: store,
            fileIO: fileIO,
            autoSaveDebounceInterval: 0
        )

        try await viewModel.load(session: session)
        viewModel.updateText("After")
        viewModel.scheduleAutosave()
        await saveGate.waitUntilWaiting()

        let blockedResult = await viewModel.saveNowResult()

        XCTAssertEqual(blockedResult.state, .failed)
        XCTAssertEqual(blockedResult.failure?.kind, .saveAlreadyInProgress)
        XCTAssertEqual(fileIO.saveAttemptCount, 1)
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .saving)

        await saveGate.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(fileIO.saveAttemptCount, 1)
        XCTAssertEqual(viewModel.autoSaveStatus?.state, .saved)
        XCTAssertEqual(viewModel.lastSaveResult?.state, .clean)
        XCTAssertEqual(viewModel.session?.saveState, .clean)
    }

    @MainActor
    func testAutoSaveCoordinatorDebouncesScheduledSave() async throws {
        let documentID = DocumentSession.ID()
        let recorder = AutoSaveRecorder()
        let coordinator = AutoSaveCoordinator(debounceInterval: 0.01) { documentID in
            await recorder.save(documentID: documentID)
        }

        coordinator.scheduleAutosave(for: documentID)
        coordinator.scheduleAutosave(for: documentID)
        try await Task.sleep(nanoseconds: 50_000_000)

        let saveCount = await recorder.saveCount
        let savedDocumentIDs = await recorder.savedDocumentIDs

        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(savedDocumentIDs, [documentID])
        XCTAssertEqual(coordinator.status(for: documentID).state, .saved)
        XCTAssertEqual(coordinator.status(for: documentID).result?.state, .clean)
    }

    @MainActor
    func testAutoSaveCoordinatorFlushRunsPendingSaveImmediately() async {
        let documentID = DocumentSession.ID()
        let recorder = AutoSaveRecorder()
        let coordinator = AutoSaveCoordinator(debounceInterval: 10) { documentID in
            await recorder.save(documentID: documentID)
        }

        coordinator.scheduleAutosave(for: documentID)
        let result = await coordinator.flush(documentID: documentID)
        let saveCount = await recorder.saveCount

        XCTAssertEqual(result.state, .clean)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(coordinator.status(for: documentID).state, .saved)
    }

    @MainActor
    func testAutoSaveCoordinatorPropagatesConflictResult() async {
        let documentID = DocumentSession.ID()
        let conflict = DocumentConflict(
            detectedAt: Date(timeIntervalSince1970: 3),
            loadedFingerprint: makeFingerprint(contentHash: "loaded"),
            currentFingerprint: makeFingerprint(contentHash: "external")
        )
        let coordinator = AutoSaveCoordinator(debounceInterval: 0) { documentID in
            .conflicted(documentID: documentID, conflict: conflict)
        }

        let result = await coordinator.flush(documentID: documentID)

        XCTAssertEqual(result.state, .conflicted)
        XCTAssertEqual(result.conflict, conflict)
        XCTAssertEqual(coordinator.status(for: documentID).state, .conflicted)
        XCTAssertEqual(coordinator.status(for: documentID).conflict, conflict)
    }

    @MainActor
    func testAutoSaveCoordinatorPropagatesSaveFailureResult() async {
        let documentID = DocumentSession.ID()
        let failure = DocumentSaveFailure(kind: .fileIO, message: "Disk is unavailable.")
        let coordinator = AutoSaveCoordinator(debounceInterval: 0) { documentID in
            .failed(documentID: documentID, failure: failure)
        }

        let result = await coordinator.flush(documentID: documentID)

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.failure, failure)
        XCTAssertEqual(coordinator.status(for: documentID).state, .failed)
        XCTAssertEqual(coordinator.status(for: documentID).failure, failure)
    }

    @MainActor
    func testAutoSaveCoordinatorCancelStopsPendingSave() async throws {
        let documentID = DocumentSession.ID()
        let recorder = AutoSaveRecorder()
        let coordinator = AutoSaveCoordinator(debounceInterval: 0.05) { documentID in
            await recorder.save(documentID: documentID)
        }

        coordinator.scheduleAutosave(for: documentID)
        let status = coordinator.cancelAutosave(for: documentID)
        try await Task.sleep(nanoseconds: 80_000_000)
        let saveCount = await recorder.saveCount

        XCTAssertEqual(status.state, .cancelled)
        XCTAssertEqual(coordinator.status(for: documentID).state, .cancelled)
        XCTAssertEqual(saveCount, 0)
    }

    @MainActor
    func testAutoSaveCoordinatorRejectsConcurrentSave() async throws {
        let documentID = DocumentSession.ID()
        let saveGate = SaveGate()
        let recorder = AutoSaveRecorder(saveGate: saveGate)
        let coordinator = AutoSaveCoordinator(debounceInterval: 0) { documentID in
            await recorder.save(documentID: documentID)
        }

        let firstSaveTask = Task { @MainActor in
            await coordinator.save(documentID: documentID)
        }
        await saveGate.waitUntilWaiting()

        let secondResult = await coordinator.save(documentID: documentID)

        XCTAssertEqual(secondResult.state, .failed)
        XCTAssertEqual(secondResult.failure?.kind, .saveAlreadyInProgress)
        let blockedSaveCount = await recorder.saveCount

        XCTAssertEqual(blockedSaveCount, 0)

        await saveGate.resume()
        let firstResult = await firstSaveTask.value
        let completedSaveCount = await recorder.saveCount

        XCTAssertEqual(firstResult.state, .clean)
        XCTAssertEqual(completedSaveCount, 1)
        XCTAssertEqual(coordinator.status(for: documentID).state, .saved)
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
    private(set) var saveAttemptCount = 0

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
        saveAttemptCount += 1

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

private actor AutoSaveRecorder {
    private let saveGate: SaveGate?
    private var documentIDs: [DocumentSession.ID] = []

    init(saveGate: SaveGate? = nil) {
        self.saveGate = saveGate
    }

    var saveCount: Int {
        documentIDs.count
    }

    var savedDocumentIDs: [DocumentSession.ID] {
        documentIDs
    }

    func save(documentID: DocumentSession.ID) async -> DocumentSaveResult {
        if let saveGate {
            await saveGate.wait()
        }

        documentIDs.append(documentID)
        return .saved(documentID: documentID)
    }
}

private enum EditorDocumentCoreTestError: Error, Equatable {
    case saveFailed
}
