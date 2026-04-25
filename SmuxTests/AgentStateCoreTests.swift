import XCTest
@testable import Smux

final class AgentStateCoreTests: XCTestCase {
    func testDetectorFindsCodexPermissionRequest() {
        let detector = AgentStatusDetector()
        let sessionID = TerminalSession.ID()

        let status = detector.detectStatus(
            from: "Codex\nDo you want to allow this command?",
            sessionID: sessionID
        )

        XCTAssertEqual(status?.agentKind, .codex)
        XCTAssertEqual(status?.state, .permissionRequested)
        XCTAssertEqual(status?.source, .terminalOutput)
        XCTAssertGreaterThanOrEqual(status?.confidence ?? 0, 0.9)
        XCTAssertEqual(status?.message, "Do you want to allow this command?")
    }

    func testDetectorCachesClaudeKindWithinSessionAndCanReset() {
        let detector = AgentStatusDetector()
        let sessionID = TerminalSession.ID()

        let running = detector.detectStatus(from: "Claude is working", sessionID: sessionID)
        let waiting = detector.detectStatus(from: "Waiting for input: choose an option", sessionID: sessionID)
        let permission = detector.detectStatus(from: "Do you want to allow this command?", sessionID: sessionID)

        XCTAssertEqual(running?.agentKind, .claude)
        XCTAssertEqual(running?.state, .running)
        XCTAssertEqual(waiting?.agentKind, .claude)
        XCTAssertEqual(waiting?.state, .waitingForInput)
        XCTAssertEqual(permission?.agentKind, .claude)
        XCTAssertEqual(permission?.state, .permissionRequested)

        detector.reset(sessionID: sessionID)
        XCTAssertNil(detector.detectStatus(from: "thinking", sessionID: sessionID))
    }

    func testDetectorIgnoresGenericTerminalFailuresWithoutAgentSignal() {
        let detector = AgentStatusDetector()

        XCTAssertNil(detector.detectStatus(from: "BUILD FAILED", sessionID: TerminalSession.ID()))
        XCTAssertNil(detector.detectStatus(from: "error: failed to compile", sessionID: TerminalSession.ID()))
    }

    func testDetectorIgnoresGenericPromptsWithoutAgentSignal() {
        let detector = AgentStatusDetector()

        XCTAssertNil(detector.detectStatus(from: "Select an option to continue", sessionID: TerminalSession.ID()))
        XCTAssertNil(detector.detectStatus(from: "Do you want to allow network access?", sessionID: TerminalSession.ID()))
    }

    @MainActor
    func testAgentStateStoreSuppressesDuplicateTransitionsButUpdatesCurrentStatus() {
        let store = AgentStateStore()
        let sessionID = TerminalSession.ID()
        let first = agentStatus(state: .waitingForInput, message: "Waiting", updatedAt: Date(timeIntervalSince1970: 1))
        let duplicate = agentStatus(state: .waitingForInput, message: "Waiting", updatedAt: Date(timeIntervalSince1970: 2))
        let completed = agentStatus(state: .completed, message: "Done", updatedAt: Date(timeIntervalSince1970: 3))

        let firstTransition = store.ingest(first, sessionID: sessionID)
        let duplicateTransition = store.ingest(duplicate, sessionID: sessionID)

        XCTAssertNotNil(firstTransition)
        XCTAssertNil(duplicateTransition)
        XCTAssertEqual(store.status(for: sessionID)?.id, duplicate.id)

        let completedTransition = store.ingest(completed, sessionID: sessionID)

        XCTAssertNotNil(completedTransition)
        XCTAssertEqual(completedTransition?.previousStatus?.id, duplicate.id)
        XCTAssertEqual(store.transitions.map(\.currentStatus.id), [first.id, completed.id])
    }

    private func agentStatus(
        id: UUID = UUID(),
        agentKind: AgentKind = .codex,
        state: AgentExecutionState,
        source: AgentStatusSource = .terminalOutput,
        message: String?,
        updatedAt: Date
    ) -> AgentStatus {
        AgentStatus(
            id: id,
            agentKind: agentKind,
            state: state,
            confidence: 0.9,
            source: source,
            message: message,
            updatedAt: updatedAt
        )
    }
}
