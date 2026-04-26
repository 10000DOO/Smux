import Foundation

nonisolated struct TerminalOutputBuffer: Equatable {
    static let defaultMaximumCharacterCount = TerminalDisplayBuffer.defaultMaximumCharacterCount

    let maximumCharacterCount: Int
    private(set) var text: String
    private var displayBuffer: TerminalDisplayBuffer
    private var pendingUTF8 = Data()

    init(
        text: String = "",
        maximumCharacterCount: Int = TerminalOutputBuffer.defaultMaximumCharacterCount
    ) {
        self.maximumCharacterCount = max(0, maximumCharacterCount)
        self.text = ""
        self.displayBuffer = TerminalDisplayBuffer(maximumCharacterCount: self.maximumCharacterCount)
        append(text)
    }

    var displayText: String {
        displayBuffer.text
    }

    mutating func append(_ output: String) {
        guard !output.isEmpty else {
            return
        }

        text.append(output)
        displayBuffer.append(output)
        truncateIfNeeded()
    }

    mutating func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        pendingUTF8.append(data)

        if let decodedText = String(data: pendingUTF8, encoding: .utf8) {
            append(decodedText)
            pendingUTF8.removeAll(keepingCapacity: true)
            return
        }

        let maximumUTF8ContinuationLength = min(3, pendingUTF8.count)
        for pendingByteCount in 1...maximumUTF8ContinuationLength {
            let decodableByteCount = pendingUTF8.count - pendingByteCount
            guard decodableByteCount > 0 else {
                continue
            }

            let decodableData = pendingUTF8.prefix(decodableByteCount)
            if let decodedText = String(data: decodableData, encoding: .utf8) {
                append(decodedText)
                pendingUTF8 = Data(pendingUTF8.suffix(pendingByteCount))
                return
            }
        }

        if pendingUTF8.count > 4 {
            append(String(decoding: pendingUTF8, as: UTF8.self))
            pendingUTF8.removeAll(keepingCapacity: true)
        }
    }

    mutating func clear() {
        text.removeAll(keepingCapacity: true)
        displayBuffer.clear()
        pendingUTF8.removeAll(keepingCapacity: true)
    }

    private mutating func truncateIfNeeded() {
        guard text.count > maximumCharacterCount else {
            return
        }

        text = String(text.suffix(maximumCharacterCount))
    }
}
