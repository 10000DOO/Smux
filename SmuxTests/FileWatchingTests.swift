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

    func testManualFileWatcherEmitsOnlyActiveScopes() throws {
        let activeURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Active.md")
        let inactiveURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace/Inactive.md")
        let watcher = ManualFileWatcher()
        let recorder = EventBatchRecorder()
        watcher.eventHandler = recorder.record

        try watcher.startWatching(.openFile(activeURL))
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

    func testManualFileWatcherStopAllStopsDelivery() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/SmuxWorkspace", isDirectory: true)
        let watcher = ManualFileWatcher()
        let recorder = EventBatchRecorder()
        watcher.eventHandler = recorder.record

        try watcher.startWatching(.workspaceRoot(rootURL))
        watcher.stopAll()
        watcher.emit(FileWatchEvent(scope: .workspaceRoot(rootURL), kind: .contentsChanged))

        XCTAssertTrue(recorder.batches.isEmpty)
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
