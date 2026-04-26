import Foundation
import XCTest
@testable import Smux

final class FileWatchingTests: XCTestCase {
    func testFileWatchEventRoundTripsThroughCodable() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace", isDirectory: true)
        let event = FileWatchEvent(
            scope: .workspaceRoot(rootURL),
            kind: .contentsChanged
        )

        let data = try JSONEncoder().encode(event)
        let decodedEvent = try JSONDecoder().decode(FileWatchEvent.self, from: data)

        XCTAssertEqual(decodedEvent, event)
        XCTAssertEqual(decodedEvent.url, rootURL)
    }

    func testDebouncerCoalescesLatestEventPerScope() {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Note.md")
        let workspaceURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace", isDirectory: true)
        let debouncer = FileWatchDebouncer(interval: 10)
        let recorder = EventBatchRecorder()
        debouncer.eventHandler = recorder.record

        debouncer.submit(FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        debouncer.submit(FileWatchEvent(scope: .workspaceRoot(workspaceURL), kind: .contentsChanged))
        debouncer.submit(FileWatchEvent(scope: .openFile(fileURL), kind: .metadataChanged))
        debouncer.flush()

        XCTAssertEqual(
            recorder.batches,
            [
                [
                    FileWatchEvent(scope: .openFile(fileURL), kind: .metadataChanged),
                    FileWatchEvent(scope: .workspaceRoot(workspaceURL), kind: .contentsChanged),
                ],
            ]
        )
    }

    func testDebouncerCancelDropsPendingEvents() {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Note.md")
        let debouncer = FileWatchDebouncer(interval: 10)
        let recorder = EventBatchRecorder()
        debouncer.eventHandler = recorder.record

        debouncer.submit(FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        debouncer.cancel()
        debouncer.flush()

        XCTAssertTrue(recorder.batches.isEmpty)
    }

    func testDebouncerCancelScopeDropsOnlyMatchingPendingEvents() {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Note.md")
        let workspaceURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace", isDirectory: true)
        let debouncer = FileWatchDebouncer(interval: 10)
        let recorder = EventBatchRecorder()
        debouncer.eventHandler = recorder.record

        debouncer.submit(FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        debouncer.submit(FileWatchEvent(scope: .workspaceRoot(workspaceURL), kind: .contentsChanged))
        debouncer.cancel(scope: .openFile(fileURL))
        debouncer.flush()

        XCTAssertEqual(
            recorder.batches,
            [
                [
                    FileWatchEvent(scope: .workspaceRoot(workspaceURL), kind: .contentsChanged),
                ],
            ]
        )
    }

    func testManualFileWatcherEmitsOnlyActiveScopes() {
        let activeURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Active.md")
        let inactiveURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Inactive.md")
        let watcher = ManualFileWatcher()
        let recorder = EventBatchRecorder()
        watcher.eventHandler = recorder.record

        watcher.startWatching(.openFile(activeURL))
        watcher.emit([
            FileWatchEvent(scope: .openFile(activeURL), kind: .modified),
            FileWatchEvent(scope: .openFile(inactiveURL), kind: .modified),
        ])

        watcher.stopWatching(.openFile(activeURL))
        watcher.emit(FileWatchEvent(scope: .openFile(activeURL), kind: .deleted))

        XCTAssertEqual(
            recorder.batches,
            [
                [
                    FileWatchEvent(scope: .openFile(activeURL), kind: .modified),
                ],
            ]
        )
    }

    func testManualFileWatcherStopAllStopsDelivery() {
        let rootURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace", isDirectory: true)
        let watcher = ManualFileWatcher()
        let recorder = EventBatchRecorder()
        watcher.eventHandler = recorder.record

        watcher.startWatching(.workspaceRoot(rootURL))
        watcher.stopAll()
        watcher.emit(FileWatchEvent(scope: .workspaceRoot(rootURL), kind: .contentsChanged))

        XCTAssertTrue(recorder.batches.isEmpty)
    }

    func testManualFileWatcherRestartRestoresDeliveryForSameScope() {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Restart.md")
        let scope = FileWatchScope.openFile(fileURL)
        let watcher = ManualFileWatcher()
        let recorder = EventBatchRecorder()
        watcher.eventHandler = recorder.record

        watcher.startWatching(scope)
        watcher.stopWatching(scope)
        watcher.emit(FileWatchEvent(scope: scope, kind: .modified))
        watcher.startWatching(scope)
        watcher.emit(FileWatchEvent(scope: scope, kind: .metadataChanged))

        XCTAssertEqual(
            recorder.batches,
            [
                [
                    FileWatchEvent(scope: scope, kind: .metadataChanged),
                ],
            ]
        )
    }

    @MainActor
    func testDocumentFileWatchStoreRoutesEventsByDocumentID() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Note.md")
        let documentID = DocumentSession.ID()
        let watcher = ManualFileWatcher()
        let store = DocumentFileWatchStore(fileWatcher: watcher)

        try store.startWatching(documentID: documentID, url: fileURL)
        watcher.emit(FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        await Task.yield()

        let routedEvent = store.latestEvent(for: documentID)
        XCTAssertEqual(routedEvent?.documentID, documentID)
        XCTAssertEqual(routedEvent?.event, FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        XCTAssertEqual(store.eventToken(for: documentID), routedEvent?.id)
    }

    @MainActor
    func testDocumentFileWatchStoreStopsDeliveryForRemovedDocument() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Removed.md")
        let documentID = DocumentSession.ID()
        let watcher = ManualFileWatcher()
        let store = DocumentFileWatchStore(fileWatcher: watcher)

        try store.startWatching(documentID: documentID, url: fileURL)
        store.stopWatching(documentID: documentID)
        watcher.emit(FileWatchEvent(scope: .openFile(fileURL), kind: .deleted))
        await Task.yield()

        XCTAssertNil(store.latestEvent(for: documentID))
        XCTAssertNil(store.eventToken(for: documentID))
    }

    @MainActor
    func testDocumentFileWatchStoreKeepsSharedScopeUntilLastDocumentStops() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Shared.md")
        let firstDocumentID = DocumentSession.ID()
        let secondDocumentID = DocumentSession.ID()
        let watcher = ManualFileWatcher()
        let store = DocumentFileWatchStore(fileWatcher: watcher)

        try store.startWatching(documentID: firstDocumentID, url: fileURL)
        try store.startWatching(documentID: secondDocumentID, url: fileURL)
        store.stopWatching(documentID: firstDocumentID)

        watcher.emit(FileWatchEvent(scope: .openFile(fileURL), kind: .renamed))
        await Task.yield()

        XCTAssertNil(store.latestEvent(for: firstDocumentID))
        XCTAssertEqual(store.latestEvent(for: secondDocumentID)?.event.kind, .renamed)
    }

    @MainActor
    func testDocumentFileWatchStoreRestartReattachesExistingScope() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Reattached.md")
        let documentID = DocumentSession.ID()
        let watcher = ManualFileWatcher()
        let store = DocumentFileWatchStore(fileWatcher: watcher)

        try store.startWatching(documentID: documentID, url: fileURL)
        watcher.stopWatching(.openFile(fileURL))
        watcher.emit(FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        await Task.yield()

        XCTAssertNil(store.latestEvent(for: documentID))

        try store.restartWatching(documentID: documentID, url: fileURL)
        watcher.emit(FileWatchEvent(scope: .openFile(fileURL), kind: .metadataChanged))
        await Task.yield()

        XCTAssertEqual(store.latestEvent(for: documentID)?.event.kind, .metadataChanged)
    }

    @MainActor
    func testDocumentFileWatchStoreRestartFailureClearsStaleMapping() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/RestartFailure.md")
        let documentID = DocumentSession.ID()
        let watcher = RestartFailureFileWatcher()
        let store = DocumentFileWatchStore(fileWatcher: watcher)

        try store.startWatching(documentID: documentID, url: fileURL)
        watcher.shouldFailStart = true

        XCTAssertThrowsError(try store.restartWatching(documentID: documentID, url: fileURL))

        watcher.shouldFailStart = false
        try store.startWatching(documentID: documentID, url: fileURL)
        watcher.emit(FileWatchEvent(scope: .openFile(fileURL), kind: .modified))
        await Task.yield()

        XCTAssertEqual(store.latestEvent(for: documentID)?.event.kind, .modified)
    }
}

private final class EventBatchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var lockedBatches: [[FileWatchEvent]] = []

    var batches: [[FileWatchEvent]] {
        lock.lock()
        defer { lock.unlock() }
        return lockedBatches
    }

    func record(_ events: [FileWatchEvent]) {
        lock.lock()
        defer { lock.unlock() }
        lockedBatches.append(events)
    }
}

private final class RestartFailureFileWatcher: FileWatching, @unchecked Sendable {
    var shouldFailStart = false
    var eventHandler: (@Sendable ([FileWatchEvent]) -> Void)?
    private var activeScopes: Set<FileWatchScope> = []

    func startWatching(_ scope: FileWatchScope) throws {
        if shouldFailStart {
            throw RestartFailureFileWatcherError.startFailed
        }

        activeScopes.insert(scope)
    }

    func stopWatching(_ scope: FileWatchScope) {
        activeScopes.remove(scope)
    }

    func stopAll() {
        activeScopes.removeAll()
    }

    func emit(_ event: FileWatchEvent) {
        guard activeScopes.contains(event.scope) else {
            return
        }

        eventHandler?([event])
    }
}

private enum RestartFailureFileWatcherError: Error {
    case startFailed
}
