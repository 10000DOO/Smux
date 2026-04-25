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
    @Published private(set) var visibleOutput: String

    private let terminalCore: (any TerminalCoreControlling)?
    private var outputBuffer: TerminalOutputBuffer

    init(
        session: TerminalSession? = nil,
        terminalCore: (any TerminalCoreControlling)? = nil,
        outputBuffer: TerminalOutputBuffer = TerminalOutputBuffer()
    ) {
        self.session = session
        self.terminalCore = terminalCore
        self.outputBuffer = outputBuffer
        self.visibleOutput = outputBuffer.text
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

    func appendOutput(_ text: String) {
        outputBuffer.append(text)
        visibleOutput = outputBuffer.text
    }

    func appendOutput(_ data: Data) {
        outputBuffer.append(data)
        visibleOutput = outputBuffer.text
    }

    func clearOutput() {
        outputBuffer.clear()
        visibleOutput = outputBuffer.text
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
