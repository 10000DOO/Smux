import Foundation

nonisolated struct TerminalOutputByteSnapshot: Equatable {
    static let empty = TerminalOutputByteSnapshot(data: Data(), startOffset: 0)

    var data: Data
    var startOffset: Int

    var endOffset: Int {
        startOffset + data.count
    }
}

nonisolated struct TerminalOutputBuffer: Equatable {
    static let defaultMaximumCharacterCount = TerminalDisplayBuffer.defaultMaximumCharacterCount

    let maximumCharacterCount: Int
    private(set) var rawData: Data
    private(set) var rawDataStartOffset: Int
    private(set) var text: String
    private var displayBuffer: TerminalDisplayBuffer
    private var pendingUTF8 = Data()

    init(
        text: String = "",
        maximumCharacterCount: Int = TerminalOutputBuffer.defaultMaximumCharacterCount
    ) {
        self.maximumCharacterCount = max(0, maximumCharacterCount)
        self.rawData = Data()
        self.rawDataStartOffset = 0
        self.text = ""
        self.displayBuffer = TerminalDisplayBuffer(maximumCharacterCount: self.maximumCharacterCount)
        append(text)
    }

    var displayText: String {
        displayBuffer.text
    }

    var displayRuns: [TerminalStyledTextRun] {
        displayBuffer.styledRuns
    }

    var displayGridSnapshot: TerminalGridSnapshot {
        displayBuffer.gridSnapshot
    }

    var rawOutputSnapshot: TerminalOutputByteSnapshot {
        TerminalOutputByteSnapshot(data: rawData, startOffset: rawDataStartOffset)
    }

    mutating func append(_ output: String) {
        guard !output.isEmpty else {
            return
        }

        appendRawData(Data(output.utf8))
        appendDecodedText(output)
    }

    private mutating func appendDecodedText(_ output: String) {
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

        appendRawData(data)
        pendingUTF8.append(data)

        if let decodedText = String(data: pendingUTF8, encoding: .utf8) {
            appendDecodedText(decodedText)
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
                appendDecodedText(decodedText)
                pendingUTF8 = Data(pendingUTF8.suffix(pendingByteCount))
                return
            }
        }

        if pendingUTF8.count > 4 {
            appendDecodedText(String(decoding: pendingUTF8, as: UTF8.self))
            pendingUTF8.removeAll(keepingCapacity: true)
        }
    }

    mutating func clear() {
        rawDataStartOffset = 0
        rawData.removeAll(keepingCapacity: true)
        text.removeAll(keepingCapacity: true)
        displayBuffer.clear()
        pendingUTF8.removeAll(keepingCapacity: true)
    }

    mutating func resize(columns: Int, rows: Int) {
        displayBuffer.resize(columns: columns, rows: rows)
    }

    private mutating func appendRawData(_ data: Data) {
        rawData.append(data)
        truncateRawDataIfNeeded()
    }

    private mutating func truncateRawDataIfNeeded() {
        guard rawData.count > maximumCharacterCount else {
            return
        }

        let removedByteCount = rawData.count - maximumCharacterCount
        rawData = Data(rawData.suffix(maximumCharacterCount))
        rawDataStartOffset += removedByteCount
    }

    private mutating func truncateIfNeeded() {
        guard text.count > maximumCharacterCount else {
            return
        }

        text = String(text.suffix(maximumCharacterCount))
    }
}
