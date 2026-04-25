import Combine
import Foundation

typealias TerminalOutputHandler = @MainActor (TerminalSession.ID, Data) -> Void

@MainActor
protocol TerminalCoreControlling: AnyObject {
    func session(for sessionID: TerminalSession.ID) -> TerminalSession?
    func sendInput(_ text: String, to sessionID: TerminalSession.ID)
    func resize(sessionID: TerminalSession.ID, columns: Int, rows: Int)
    func terminate(sessionID: TerminalSession.ID)
}

enum TerminalSessionControllerError: LocalizedError, Equatable {
    case emptyExecutable
    case failedToStart(sessionID: TerminalSession.ID, reason: String)

    var errorDescription: String? {
        switch self {
        case .emptyExecutable:
            return "Terminal command is empty."
        case let .failedToStart(_, reason):
            return "Failed to start terminal session: \(reason)"
        }
    }
}

@MainActor
final class TerminalSessionController: ObservableObject, TerminalCoreControlling {
    @Published var sessions: [TerminalSession.ID: TerminalSession] = [:]

    private let ptyFactory: any PTYClientFactory
    private let outputHandler: TerminalOutputHandler?
    private let clock: () -> Date
    private var ptyClients: [TerminalSession.ID: any PTYClient] = [:]

    init(
        ptyFactory: any PTYClientFactory = LocalPTYClientFactory(),
        outputHandler: TerminalOutputHandler? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        self.ptyFactory = ptyFactory
        self.outputHandler = outputHandler
        self.clock = clock
    }

    func createSession(in workspace: Workspace, command: [String]) async throws -> TerminalSession {
        let createdAt = clock()
        let launch = try makeLaunchRequest(command: command, workingDirectory: workspace.rootURL)
        let sessionID = TerminalSession.ID()
        var session = TerminalSession(
            id: sessionID,
            workspaceID: workspace.id,
            workingDirectory: workspace.rootURL,
            processID: nil,
            shell: launch.shell,
            command: launch.command,
            status: .starting,
            title: launch.title,
            createdAt: createdAt,
            lastActivityAt: createdAt,
            lastOutputSummary: nil,
            exitCode: nil,
            failureMessage: nil
        )
        sessions[sessionID] = session

        let ptyClient = ptyFactory.makeClient()
        ptyClient.outputHandler = { [weak self] data in
            Task { @MainActor in
                self?.receiveOutput(data, for: sessionID)
            }
        }
        ptyClient.terminationHandler = { [weak self] exitCode in
            Task { @MainActor in
                self?.finishSession(sessionID, exitCode: exitCode)
            }
        }

        do {
            let result = try ptyClient.start(launch.request)
            session.processID = result.processID
            session.status = .running
            session.lastActivityAt = clock()
            sessions[sessionID] = session
            ptyClients[sessionID] = ptyClient
            return session
        } catch {
            ptyClient.terminate()
            let reason = error.localizedDescription
            session.status = .failed
            session.failureMessage = reason
            session.lastActivityAt = clock()
            sessions[sessionID] = session
            throw TerminalSessionControllerError.failedToStart(sessionID: sessionID, reason: reason)
        }
    }

    func session(for sessionID: TerminalSession.ID) -> TerminalSession? {
        sessions[sessionID]
    }

    func sendInput(_ text: String, to sessionID: TerminalSession.ID) {
        guard let data = text.data(using: .utf8), !data.isEmpty else {
            return
        }

        guard let ptyClient = ptyClients[sessionID] else {
            failRunningSession(sessionID, reason: "Terminal session is not running.")
            return
        }

        do {
            try ptyClient.write(data)
            touchSession(sessionID)
        } catch {
            failSession(sessionID, reason: error.localizedDescription)
        }
    }

    func resize(sessionID: TerminalSession.ID, columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else {
            return
        }

        guard let ptyClient = ptyClients[sessionID] else {
            failRunningSession(sessionID, reason: "Terminal session is not running.")
            return
        }

        do {
            try ptyClient.resize(columns: columns, rows: rows)
            touchSession(sessionID)
        } catch {
            failSession(sessionID, reason: error.localizedDescription)
        }
    }

    func terminate(sessionID: TerminalSession.ID) {
        guard var session = sessions[sessionID],
              session.status == .starting || session.status == .running else {
            return
        }

        ptyClients.removeValue(forKey: sessionID)?.terminate()
        session.status = .terminated
        session.lastActivityAt = clock()
        sessions[sessionID] = session
    }

    private func makeLaunchRequest(
        command: [String],
        workingDirectory: URL
    ) throws -> TerminalLaunch {
        if command.isEmpty {
            let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let executableURL = URL(fileURLWithPath: shellPath)
            let request = PTYLaunchRequest(
                executableURL: executableURL,
                arguments: [],
                workingDirectory: workingDirectory,
                environment: ProcessInfo.processInfo.environment,
                columns: 80,
                rows: 24
            )
            return TerminalLaunch(
                request: request,
                command: [shellPath],
                shell: shellPath,
                title: executableURL.lastPathComponent
            )
        }

        guard let executable = command.first, !executable.isEmpty else {
            throw TerminalSessionControllerError.emptyExecutable
        }

        let executableURL: URL
        let arguments: [String]
        if executable.contains("/") {
            executableURL = URL(fileURLWithPath: executable)
            arguments = Array(command.dropFirst())
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = command
        }

        let request = PTYLaunchRequest(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: ProcessInfo.processInfo.environment,
            columns: 80,
            rows: 24
        )

        return TerminalLaunch(
            request: request,
            command: command,
            shell: nil,
            title: command.joined(separator: " ")
        )
    }

    private func receiveOutput(_ data: Data, for sessionID: TerminalSession.ID) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.lastActivityAt = clock()
        session.lastOutputSummary = String(data: data.prefix(256), encoding: .utf8)
        sessions[sessionID] = session
        outputHandler?(sessionID, data)
    }

    private func finishSession(_ sessionID: TerminalSession.ID, exitCode: Int32) {
        guard var session = sessions[sessionID] else {
            return
        }

        if session.status != .failed {
            session.status = .terminated
        }
        session.exitCode = exitCode
        session.lastActivityAt = clock()
        sessions[sessionID] = session
        ptyClients.removeValue(forKey: sessionID)
    }

    private func touchSession(_ sessionID: TerminalSession.ID) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.lastActivityAt = clock()
        sessions[sessionID] = session
    }

    private func failSession(_ sessionID: TerminalSession.ID, reason: String) {
        guard var session = sessions[sessionID] else {
            return
        }
        guard session.status == .running else {
            return
        }

        session.status = .failed
        session.failureMessage = reason
        session.lastActivityAt = clock()
        sessions[sessionID] = session
        ptyClients.removeValue(forKey: sessionID)?.terminate()
    }

    private func failRunningSession(_ sessionID: TerminalSession.ID, reason: String) {
        guard sessions[sessionID]?.status == .running else {
            return
        }

        failSession(sessionID, reason: reason)
    }
}

private struct TerminalLaunch {
    var request: PTYLaunchRequest
    var command: [String]
    var shell: String?
    var title: String
}
