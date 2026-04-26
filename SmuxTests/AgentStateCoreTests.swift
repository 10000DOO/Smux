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

    func testDetectorMapsHookPayloadToPermissionRequest() {
        let detector = AgentStatusDetector()
        let sessionID = TerminalSession.ID()
        let occurredAt = Date(timeIntervalSince1970: 100)

        let status = detector.detectStatus(
            from: AgentHookPayload(
                agentKind: .codex,
                eventName: "PermissionRequest",
                body: "Approve command execution?",
                occurredAt: occurredAt
            ),
            sessionID: sessionID
        )

        XCTAssertEqual(status?.agentKind, .codex)
        XCTAssertEqual(status?.state, .permissionRequested)
        XCTAssertEqual(status?.source, .hookPayload)
        XCTAssertEqual(status?.message, "Approve command execution?")
        XCTAssertEqual(status?.updatedAt, occurredAt)
        XCTAssertGreaterThanOrEqual(status?.confidence ?? 0, 0.9)
    }

    func testDetectorMapsClaudeNotificationHookToWaitingForInput() {
        let detector = AgentStatusDetector()

        let status = detector.detectStatus(
            from: AgentHookPayload(
                agentKind: .claude,
                eventName: "Notification",
                title: "Claude needs input",
                body: "Please respond before continuing."
            ),
            sessionID: TerminalSession.ID()
        )

        XCTAssertEqual(status?.agentKind, .claude)
        XCTAssertEqual(status?.state, .waitingForInput)
        XCTAssertEqual(status?.source, .hookPayload)
        XCTAssertEqual(status?.message, "Please respond before continuing.")
    }

    func testDetectorMapsHookStopToCompleted() {
        let detector = AgentStatusDetector()

        let status = detector.detectStatus(
            from: AgentHookPayload(
                agentKind: .codex,
                eventName: "Stop",
                message: "Codex completed successfully"
            ),
            sessionID: TerminalSession.ID()
        )

        XCTAssertEqual(status?.agentKind, .codex)
        XCTAssertEqual(status?.state, .completed)
        XCTAssertEqual(status?.source, .hookPayload)
        XCTAssertEqual(status?.message, "Codex completed successfully")
    }

    func testDetectorMapsNotificationPermissionDeniedToFailed() {
        let detector = AgentStatusDetector()

        let status = detector.detectStatus(
            from: AgentHookPayload(
                agentKind: .claude,
                eventName: "Notification",
                body: "Permission denied by user."
            ),
            sessionID: TerminalSession.ID()
        )

        XCTAssertEqual(status?.agentKind, .claude)
        XCTAssertEqual(status?.state, .failed)
        XCTAssertEqual(status?.source, .hookPayload)
        XCTAssertEqual(status?.message, "Permission denied by user.")
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

    @MainActor
    func testAgentStateStoreSuppressesDuplicateTransitionsAcrossSources() {
        let store = AgentStateStore()
        let sessionID = TerminalSession.ID()
        let terminalStatus = agentStatus(
            state: .permissionRequested,
            source: .terminalOutput,
            message: "Approve command?",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let hookStatus = agentStatus(
            state: .permissionRequested,
            source: .hookPayload,
            message: "Approve command?",
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let firstTransition = store.ingest(terminalStatus, sessionID: sessionID)
        let duplicateTransition = store.ingest(hookStatus, sessionID: sessionID)

        XCTAssertNotNil(firstTransition)
        XCTAssertNil(duplicateTransition)
        XCTAssertEqual(store.status(for: sessionID)?.id, hookStatus.id)
        XCTAssertEqual(store.transitions.map(\.currentStatus.id), [terminalStatus.id])
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
