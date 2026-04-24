import Combine
import Foundation

@MainActor
final class TerminalSessionController: ObservableObject {
    @Published var sessions: [TerminalSession.ID: TerminalSession] = [:]

    func createSession(in workspace: Workspace, command: [String]) async throws -> TerminalSession {
        fatalError("TODO")
    }

    func terminate(sessionID: TerminalSession.ID) {}
}
