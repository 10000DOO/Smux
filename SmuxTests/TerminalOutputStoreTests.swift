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

    func testAppendPreservesSplitUTF8Scalars() {
        let sessionID = TerminalSession.ID()
        let store = TerminalOutputStore()
        let bytes = Array("한".utf8)

        store.append(Data(bytes.prefix(1)), for: sessionID)
        store.append(Data(bytes.dropFirst()), for: sessionID)

        XCTAssertEqual(store.output(for: sessionID), "한")
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
    }
}
