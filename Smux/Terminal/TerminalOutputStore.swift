import Combine
import Foundation

@MainActor
final class TerminalOutputStore: ObservableObject {
    @Published private var revision = 0

    private var buffers: [TerminalSession.ID: TerminalOutputBuffer] = [:]
    private let maximumCharacterCount: Int

    init(maximumCharacterCount: Int = TerminalOutputBuffer.defaultMaximumCharacterCount) {
        self.maximumCharacterCount = maximumCharacterCount
    }

    func output(for sessionID: TerminalSession.ID) -> String {
        buffers[sessionID]?.displayText ?? ""
    }

    func styledOutput(for sessionID: TerminalSession.ID) -> [TerminalStyledTextRun] {
        buffers[sessionID]?.displayRuns ?? []
    }

    func gridSnapshot(for sessionID: TerminalSession.ID) -> TerminalGridSnapshot {
        buffers[sessionID]?.displayGridSnapshot ?? .empty
    }

    func append(_ data: Data, for sessionID: TerminalSession.ID) {
        var buffer = buffers[sessionID] ?? TerminalOutputBuffer(maximumCharacterCount: maximumCharacterCount)
        buffer.append(data)
        buffers[sessionID] = buffer
        publishOutputChange()
    }

    func append(_ text: String, for sessionID: TerminalSession.ID) {
        var buffer = buffers[sessionID] ?? TerminalOutputBuffer(maximumCharacterCount: maximumCharacterCount)
        buffer.append(text)
        buffers[sessionID] = buffer
        publishOutputChange()
    }

    func clear(sessionID: TerminalSession.ID) {
        guard buffers.removeValue(forKey: sessionID) != nil else {
            return
        }

        publishOutputChange()
    }

    func clearAll() {
        guard !buffers.isEmpty else {
            return
        }

        buffers.removeAll()
        publishOutputChange()
    }

    private func publishOutputChange() {
        revision &+= 1
    }
}
