import Combine
import Foundation

@MainActor
final class TerminalOutputStore: ObservableObject {
    @Published private var outputs: [TerminalSession.ID: String] = [:]
    @Published private var styledOutputs: [TerminalSession.ID: [TerminalStyledTextRun]] = [:]

    private var buffers: [TerminalSession.ID: TerminalOutputBuffer] = [:]
    private let maximumCharacterCount: Int

    init(maximumCharacterCount: Int = TerminalOutputBuffer.defaultMaximumCharacterCount) {
        self.maximumCharacterCount = maximumCharacterCount
    }

    func output(for sessionID: TerminalSession.ID) -> String {
        outputs[sessionID] ?? ""
    }

    func styledOutput(for sessionID: TerminalSession.ID) -> [TerminalStyledTextRun] {
        styledOutputs[sessionID] ?? []
    }

    func append(_ data: Data, for sessionID: TerminalSession.ID) {
        var buffer = buffers[sessionID] ?? TerminalOutputBuffer(maximumCharacterCount: maximumCharacterCount)
        buffer.append(data)
        buffers[sessionID] = buffer
        updateOutput(for: sessionID, from: buffer)
    }

    func append(_ text: String, for sessionID: TerminalSession.ID) {
        var buffer = buffers[sessionID] ?? TerminalOutputBuffer(maximumCharacterCount: maximumCharacterCount)
        buffer.append(text)
        buffers[sessionID] = buffer
        updateOutput(for: sessionID, from: buffer)
    }

    func clear(sessionID: TerminalSession.ID) {
        buffers.removeValue(forKey: sessionID)
        outputs.removeValue(forKey: sessionID)
        styledOutputs.removeValue(forKey: sessionID)
    }

    func clearAll() {
        buffers.removeAll()
        outputs.removeAll()
        styledOutputs.removeAll()
    }

    private func updateOutput(for sessionID: TerminalSession.ID, from buffer: TerminalOutputBuffer) {
        outputs[sessionID] = buffer.displayText
        styledOutputs[sessionID] = buffer.displayRuns
    }
}
