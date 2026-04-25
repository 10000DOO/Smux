import Combine
import Foundation

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var session: TerminalSession? {
        didSet {
            updateMetadata()
        }
    }
    @Published var status: TerminalSessionStatus = .idle
    @Published var title = "Terminal"

    private let terminalCore: (any TerminalCoreControlling)?

    init(
        session: TerminalSession? = nil,
        terminalCore: (any TerminalCoreControlling)? = nil
    ) {
        self.session = session
        self.terminalCore = terminalCore
        updateMetadata()
    }

    func sendInput(_ text: String) {
        guard let sessionID = session?.id else {
            return
        }

        terminalCore?.sendInput(text, to: sessionID)
        refreshSession()
    }

    func resize(columns: Int, rows: Int) {
        guard let sessionID = session?.id else {
            return
        }

        terminalCore?.resize(sessionID: sessionID, columns: columns, rows: rows)
        refreshSession()
    }

    private func refreshSession() {
        guard let sessionID = session?.id,
              let updatedSession = terminalCore?.session(for: sessionID) else {
            return
        }

        session = updatedSession
    }

    private func updateMetadata() {
        status = session?.status ?? .idle
        title = session?.title ?? "Terminal"
    }
}
