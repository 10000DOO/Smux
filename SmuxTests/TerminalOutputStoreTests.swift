import Combine
import XCTest
@testable import Smux

@MainActor
final class TerminalOutputStoreTests: XCTestCase {
    func testAppendPreservesFullOutputPerSession() {
        let firstSessionID = TerminalSession.ID()
        let secondSessionID = TerminalSession.ID()
        let store = TerminalOutputStore()

        store.append(Data("first ".utf8), for: firstSessionID)
        store.append(Data("chunk".utf8), for: firstSessionID)
        store.append(Data("second".utf8), for: secondSessionID)

        XCTAssertEqual(store.output(for: firstSessionID), "first chunk")
        XCTAssertEqual(store.output(for: secondSessionID), "second")
    }

    func testAppendPreservesRawPTYBytesForTerminalEmulatorCore() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()
        let output = Data([0x1B, 0x5B, 0x33, 0x31, 0x6D, 0x41])

        store.append(output, for: sessionID)

        XCTAssertEqual(store.rawOutputData(for: sessionID), output)
    }

    func testRawOutputSnapshotTracksTrimmedByteOffset() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore(maximumCharacterCount: 3)

        store.append(Data("abcde".utf8), for: sessionID)

        let snapshot = store.rawOutputSnapshot(for: sessionID)
        XCTAssertEqual(snapshot.data, Data("cde".utf8))
        XCTAssertEqual(snapshot.startOffset, 2)
        XCTAssertEqual(snapshot.endOffset, 5)
    }

    func testAppendPreservesSplitUTF8Scalars() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()
        let bytes = Array("한".utf8)

        store.append(Data(bytes.prefix(1)), for: sessionID)
        store.append(Data(bytes.dropFirst()), for: sessionID)

        XCTAssertEqual(store.output(for: sessionID), "한")
    }

    func testOutputUsesCleanDisplayText() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()

        store.append("old\r\u{1B}[K\u{1B}[32mnew\u{1B}[0m", for: sessionID)

        XCTAssertEqual(store.output(for: sessionID), "new")
    }

    func testStyledOutputPreservesANSIRuns() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()

        store.append("\u{1B}[32mnew\u{1B}[0m plain", for: sessionID)

        XCTAssertEqual(
            store.styledOutput(for: sessionID),
            [
                TerminalStyledTextRun(
                    text: "new",
                    style: TerminalTextStyle(
                        foreground: .ansi(.green),
                        background: nil,
                        isBold: false,
                        isItalic: false,
                        isUnderline: false
                    )
                ),
                TerminalStyledTextRun(text: " plain", style: .default)
            ]
        )
    }

    func testGridSnapshotPreservesStyledDisplayCells() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()

        store.append("\u{1B}[34m한\u{1B}[0m!", for: sessionID)

        let snapshot = store.gridSnapshot(for: sessionID)
        XCTAssertEqual(snapshot.text, "한!")
        XCTAssertEqual(snapshot.lines.first?.displayWidth, 3)
        XCTAssertEqual(snapshot.lines.first?.cells.map(\.width), [2, 1])
        XCTAssertEqual(snapshot.lines.first?.cells.first?.style.foreground, .ansi(.blue))
    }

    func testResizeUpdatesTerminalDisplayRowsForAlternateScreen() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()

        store.resize(sessionID: sessionID, columns: 10, rows: 2)
        store.append("\u{1B}[?1049h1\n2\n3", for: sessionID)

        XCTAssertEqual(store.output(for: sessionID), "2\n3")
    }

    func testAppendPublishesSingleChangePerChunk() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()
        var changeCount = 0
        var cancellable: AnyCancellable?
        cancellable = store.objectWillChange.sink {
            changeCount += 1
        }

        store.append("chunk", for: sessionID)

        XCTAssertEqual(changeCount, 1)
        _ = cancellable
    }

    func testClearRemovesOnlyRequestedSessionOutput() {
        let firstSessionID = TerminalSession.ID()
        let secondSessionID = TerminalSession.ID()
        let store = TerminalOutputStore()

        store.append("first", for: firstSessionID)
        store.append("second", for: secondSessionID)
        store.clear(sessionID: firstSessionID)

        XCTAssertEqual(store.output(for: firstSessionID), "")
        XCTAssertEqual(store.output(for: secondSessionID), "second")
        XCTAssertEqual(store.styledOutput(for: firstSessionID), [])
        XCTAssertEqual(store.gridSnapshot(for: firstSessionID), .empty)
    }
}
