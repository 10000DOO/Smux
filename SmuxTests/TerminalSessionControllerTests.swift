import Darwin
import XCTest
@testable import Smux

@MainActor
final class TerminalSessionControllerTests: XCTestCase {
    func testCreateSessionStartsShellInWorkspaceAndStoresMetadata() async throws {
        let clock = IncrementingClock()
        let client = MockPTYClient(processID: 4321)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client),
            clock: clock.now
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalMetadata")

        let session = try await controller.createSession(in: workspace, command: [])

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        XCTAssertEqual(client.startRequests.count, 1)
        XCTAssertEqual(client.startRequests.first?.executableURL.path, shellPath)
        XCTAssertEqual(client.startRequests.first?.arguments, ["-l"])
        XCTAssertEqual(client.startRequests.first?.workingDirectory, workspace.rootURL)
        XCTAssertEqual(client.startRequests.first?.environment?["TERM_PROGRAM"], "Smux")
        XCTAssertFalse((client.startRequests.first?.environment?["TERM"] ?? "").isEmpty)
        XCTAssertNotEqual(client.startRequests.first?.environment?["TERM"], "dumb")
        XCTAssertEqual(session.workspaceID, workspace.id)
        XCTAssertEqual(session.workingDirectory, workspace.rootURL)
        XCTAssertEqual(session.processID, 4321)
        XCTAssertEqual(session.shell, shellPath)
        XCTAssertEqual(session.command, [shellPath, "-l"])
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.title, URL(fileURLWithPath: shellPath).lastPathComponent)
        XCTAssertEqual(session.createdAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(session.lastActivityAt, Date(timeIntervalSince1970: 2))
        XCTAssertNil(session.failureMessage)
        XCTAssertEqual(controller.sessions[session.id], session)
    }

    func testCreateSessionStartsExplicitCommandThroughEnvironmentLookup() async throws {
        let client = MockPTYClient(processID: 987)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client)
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalCommand")

        let session = try await controller.createSession(
            in: workspace,
            command: ["echo", "hello"]
        )

        XCTAssertEqual(client.startRequests.first?.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(client.startRequests.first?.arguments, ["echo", "hello"])
        XCTAssertEqual(client.startRequests.first?.workingDirectory, workspace.rootURL)
        XCTAssertEqual(client.startRequests.first?.environment?["TERM_PROGRAM"], "Smux")
        XCTAssertNotEqual(client.startRequests.first?.environment?["TERM"], "dumb")
        XCTAssertNil(session.shell)
        XCTAssertEqual(session.command, ["echo", "hello"])
        XCTAssertEqual(session.title, "echo hello")
        XCTAssertEqual(session.status, .running)
    }

    func testCreateSessionStoresFailedSessionWhenPTYStartFails() async {
        let client = MockPTYClient(startError: MockPTYError.startFailed)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client)
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalStartFailure")

        do {
            _ = try await controller.createSession(in: workspace, command: ["false"])
            XCTFail("Expected createSession to throw")
        } catch let error as TerminalSessionControllerError {
            guard case let .failedToStart(sessionID, reason) = error else {
                XCTFail("Expected failedToStart error")
                return
            }
            let failedSession = controller.sessions[sessionID]
            XCTAssertEqual(reason, "Mock PTY start failed.")
            XCTAssertEqual(failedSession?.status, .failed)
            XCTAssertEqual(failedSession?.failureMessage, "Mock PTY start failed.")
            XCTAssertNil(failedSession?.processID)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOutputAndTerminateUpdateLifecycleState() async throws {
        let clock = IncrementingClock()
        let client = MockPTYClient(processID: 101)
        var outputs: [(TerminalSession.ID, String)] = []
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client),
            outputHandler: { sessionID, data in
                outputs.append((sessionID, String(data: data, encoding: .utf8) ?? ""))
            },
            clock: clock.now
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalLifecycle")
        let session = try await controller.createSession(in: workspace, command: ["swift", "--version"])

        client.emitOutput("ready")
        await Task.yield()

        XCTAssertEqual(controller.sessions[session.id]?.lastOutputSummary, "ready")
        XCTAssertEqual(outputs.first?.0, session.id)
        XCTAssertEqual(outputs.first?.1, "ready")

        controller.terminate(sessionID: session.id)

        XCTAssertEqual(client.terminateCallCount, 1)
        XCTAssertEqual(controller.sessions[session.id]?.status, .terminated)

        client.exit(code: 0)
        await Task.yield()

        XCTAssertEqual(controller.sessions[session.id]?.exitCode, 0)
        XCTAssertEqual(controller.sessions[session.id]?.status, .terminated)
    }

    func testSendInputAndResizeDelegateToPTYClient() async throws {
        let client = MockPTYClient(processID: 202)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client)
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalInput")
        let session = try await controller.createSession(in: workspace, command: ["cat"])

        controller.sendInput("hello\n", to: session.id)
        controller.resize(sessionID: session.id, columns: 120, rows: 40)

        XCTAssertEqual(client.writes, [Data("hello\n".utf8)])
        XCTAssertEqual(client.resizes.map(\.columns), [120])
        XCTAssertEqual(client.resizes.map(\.rows), [40])
        XCTAssertEqual(controller.sessions[session.id]?.status, .running)
    }

    func testSendInputFailureMarksSessionFailed() async throws {
        let client = MockPTYClient(processID: 303)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client)
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalWriteFailure")
        let session = try await controller.createSession(in: workspace, command: ["cat"])

        client.writeError = MockPTYError.writeFailed
        controller.sendInput("hello", to: session.id)

        XCTAssertEqual(controller.sessions[session.id]?.status, .failed)
        XCTAssertEqual(controller.sessions[session.id]?.failureMessage, "Mock PTY write failed.")
    }

    func testSendInputAfterTerminateDoesNotMarkSessionFailed() async throws {
        let client = MockPTYClient(processID: 404)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client)
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalLateInput")
        let session = try await controller.createSession(in: workspace, command: ["cat"])

        controller.terminate(sessionID: session.id)
        controller.sendInput("late input", to: session.id)

        XCTAssertEqual(controller.sessions[session.id]?.status, .terminated)
        XCTAssertNil(controller.sessions[session.id]?.failureMessage)
        XCTAssertTrue(client.writes.isEmpty)
    }

    func testRemoveSessionTerminatesClientAndDropsStoredSession() async throws {
        let client = MockPTYClient(processID: 505)
        let controller = TerminalSessionController(
            ptyFactory: MockPTYClientFactory(client: client)
        )
        let workspace = makeWorkspace(path: "/tmp/SmuxTerminalRemove")
        let session = try await controller.createSession(in: workspace, command: ["cat"])

        controller.removeSession(sessionID: session.id)
        client.exit(code: 0)
        await Task.yield()

        XCTAssertEqual(client.terminateCallCount, 1)
        XCTAssertNil(controller.session(for: session.id))
        XCTAssertNil(controller.sessions[session.id])
    }

    func testLocalPTYClientWriteRetriesEINTRAndCompletesPartialWrites() throws {
        var callCount = 0
        var chunks: [Data] = []
        let client = LocalPTYClient(masterFileDescriptor: 7) { descriptor, pointer, count in
            XCTAssertEqual(descriptor, 7)
            callCount += 1

            if callCount == 1 {
                errno = EINTR
                return -1
            }

            let chunkSize = min(2, count)
            if let pointer {
                chunks.append(Data(bytes: pointer, count: chunkSize))
            }
            return chunkSize
        }

        try client.write(Data("abcdef".utf8))

        XCTAssertEqual(callCount, 4)
        XCTAssertEqual(chunks.map { String(data: $0, encoding: .utf8) }, ["ab", "cd", "ef"])
    }

    private func makeWorkspace(path: String) -> Workspace {
        Workspace.make(
            id: UUID(),
            rootURL: URL(fileURLWithPath: path),
            openedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class MockPTYClient: PTYClient {
    var outputHandler: (@Sendable (Data) -> Void)?
    var terminationHandler: (@Sendable (Int32) -> Void)?
    private(set) var processID: Int32?
    private(set) var startRequests: [PTYLaunchRequest] = []
    private(set) var writes: [Data] = []
    private(set) var resizes: [(columns: Int, rows: Int)] = []
    private(set) var terminateCallCount = 0
    var writeError: (any Error)?
    var resizeError: (any Error)?

    private let startError: (any Error)?
    private let launchProcessID: Int32

    init(processID: Int32 = 1, startError: (any Error)? = nil) {
        self.launchProcessID = processID
        self.startError = startError
    }

    func start(_ request: PTYLaunchRequest) throws -> PTYLaunchResult {
        startRequests.append(request)
        if let startError {
            throw startError
        }

        processID = launchProcessID
        return PTYLaunchResult(processID: launchProcessID)
    }

    func write(_ data: Data) throws {
        if let writeError {
            throw writeError
        }

        writes.append(data)
    }

    func resize(columns: Int, rows: Int) throws {
        if let resizeError {
            throw resizeError
        }

        resizes.append((columns: columns, rows: rows))
    }

    func terminate() {
        terminateCallCount += 1
    }

    func emitOutput(_ text: String) {
        outputHandler?(Data(text.utf8))
    }

    func exit(code: Int32) {
        terminationHandler?(code)
    }
}

private final class MockPTYClientFactory: PTYClientFactory, @unchecked Sendable {
    private let client: MockPTYClient

    init(client: MockPTYClient) {
        self.client = client
    }

    func makeClient() -> any PTYClient {
        client
    }
}

private enum MockPTYError: LocalizedError {
    case startFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            return "Mock PTY start failed."
        case .writeFailed:
            return "Mock PTY write failed."
        }
    }
}

private final class IncrementingClock {
    private var value: TimeInterval = 1

    func now() -> Date {
        defer { value += 1 }
        return Date(timeIntervalSince1970: value)
    }
}
