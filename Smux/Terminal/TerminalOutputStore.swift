import Combine
import Foundation

@MainActor
final class TerminalOutputStore: ObservableObject {
    @Published private var outputs: [TerminalSession.ID: String] = [:]

    private var buffers: [TerminalSession.ID: TerminalOutputBuffer] = [:]
    private let maximumCharacterCount: Int

    init(maximumCharacterCount: Int = TerminalOutputBuffer.defaultMaximumCharacterCount) {
        self.maximumCharacterCount = maximumCharacterCount
    }

    func output(for sessionID: TerminalSession.ID) -> String {
        outputs[sessionID] ?? ""
    }

    func append(_ data: Data, for sessionID: TerminalSession.ID) {
        var buffer = buffers[sessionID] ?? TerminalOutputBuffer(maximumCharacterCount: maximumCharacterCount)
        buffer.append(data)
        buffers[sessionID] = buffer
        outputs[sessionID] = buffer.displayText
    }

    func append(_ text: String, for sessionID: TerminalSession.ID) {
        var buffer = buffers[sessionID] ?? TerminalOutputBuffer(maximumCharacterCount: maximumCharacterCount)
        buffer.append(text)
        buffers[sessionID] = buffer
        outputs[sessionID] = buffer.displayText
    }

    func clear(sessionID: TerminalSession.ID) {
        buffers.removeValue(forKey: sessionID)
        outputs.removeValue(forKey: sessionID)
    }

    func clearAll() {
        buffers.removeAll()
        outputs.removeAll()
    }
}
