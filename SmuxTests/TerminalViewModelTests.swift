import XCTest
@testable import Smux

@MainActor
final class TerminalViewModelTests: XCTestCase {
    func testSendInputAndResizeDelegateToTerminalCoreAndRefreshMetadata() {
        let sessionID = TerminalSession.ID()
        let initialSession = makeSession(
            id: sessionID,
            status: .running,
            title: "cat"
        )
        let updatedSession = makeSession(
            id: sessionID,
            status: .failed,
            title: "cat",
            failureMessage: "Write failed"
        )
        let core = MockTerminalCore()
        core.sessions[sessionID] = updatedSession
        let viewModel = TerminalViewModel(
            session: initialSession,
            terminalCore: core
        )

        viewModel.sendInput("hello")
        viewModel.resize(columns: 100, rows: 30)

        XCTAssertEqual(core.sentInputs.map(\.text), ["hello"])
        XCTAssertEqual(core.sentInputs.map(\.sessionID), [sessionID])
        XCTAssertEqual(core.resizes.map(\.sessionID), [sessionID])
        XCTAssertEqual(core.resizes.map(\.columns), [100])
        XCTAssertEqual(core.resizes.map(\.rows), [30])
        XCTAssertEqual(viewModel.session, updatedSession)
        XCTAssertEqual(viewModel.status, .failed)
        XCTAssertEqual(viewModel.title, "cat")
    }

    private func makeSession(
        id: TerminalSession.ID,
        status: TerminalSessionStatus,
        title: String,
        failureMessage: String? = nil
    ) -> TerminalSession {
        TerminalSession(
            id: id,
            workspaceID: UUID(),
            workingDirectory: URL(fileURLWithPath: "/tmp/SmuxTerminalViewModel"),
            processID: 1,
            shell: nil,
            command: ["cat"],
            status: status,
            title: title,
            createdAt: Date(timeIntervalSince1970: 1),
            lastActivityAt: Date(timeIntervalSince1970: 1),
            lastOutputSummary: nil,
            exitCode: nil,
            failureMessage: failureMessage
        )
    }
}

@MainActor
private final class MockTerminalCore: TerminalCoreControlling {
    var sessions: [TerminalSession.ID: TerminalSession] = [:]
    private(set) var sentInputs: [(text: String, sessionID: TerminalSession.ID)] = []
    private(set) var resizes: [(sessionID: TerminalSession.ID, columns: Int, rows: Int)] = []

    func session(for sessionID: TerminalSession.ID) -> TerminalSession? {
        sessions[sessionID]
    }

    func sendInput(_ text: String, to sessionID: TerminalSession.ID) {
        sentInputs.append((text: text, sessionID: sessionID))
    }

    func resize(sessionID: TerminalSession.ID, columns: Int, rows: Int) {
        resizes.append((sessionID: sessionID, columns: columns, rows: rows))
    }

    func terminate(sessionID: TerminalSession.ID) {}
}
