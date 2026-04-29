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
    @Published private(set) var visibleStyledOutput: [TerminalStyledTextRun]

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
        self.visibleOutput = outputBuffer.displayText
        self.visibleStyledOutput = outputBuffer.displayRuns
        updateMetadata()
    }

    func sendInput(_ text: String) {
        guard let sessionID = session?.id else {
            return
        }

        terminalCore?.sendInput(text, to: sessionID)
        refreshSession()
    }

    func sendInput(_ data: Data) {
        guard let sessionID = session?.id else {
            return
        }

        terminalCore?.sendInput(data, to: sessionID)
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
        publishOutput()
    }

    func appendOutput(_ data: Data) {
        outputBuffer.append(data)
        publishOutput()
    }

    func clearOutput() {
        outputBuffer.clear()
        publishOutput()
    }

    private func refreshSession() {
        guard let sessionID = session?.id,
              let updatedSession = terminalCore?.session(for: sessionID) else {
            return
        }
        guard session != updatedSession else {
            return
        }

        session = updatedSession
    }

    private func updateMetadata() {
        let nextStatus = session?.status ?? .idle
        if status != nextStatus {
            status = nextStatus
        }

        let nextTitle = session?.title ?? "Terminal"
        if title != nextTitle {
            title = nextTitle
        }
    }

    private func publishOutput() {
        visibleOutput = outputBuffer.displayText
        visibleStyledOutput = outputBuffer.displayRuns
    }
}
