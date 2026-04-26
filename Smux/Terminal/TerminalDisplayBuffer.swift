import Foundation

nonisolated struct TerminalDisplayBuffer: Equatable {
    static let defaultMaximumCharacterCount = 200_000

    let maximumCharacterCount: Int

    private var lines: [[Character]]
    private var cursorLineIndex: Int
    private var cursorColumn: Int
    private var parserState: ParserState = .normal
    private var carriageReturnPending = false

    var text: String {
        lines.map { String($0) }.joined(separator: "\n")
    }

    init(
        text: String = "",
        maximumCharacterCount: Int = TerminalDisplayBuffer.defaultMaximumCharacterCount
    ) {
        self.maximumCharacterCount = max(0, maximumCharacterCount)
        self.lines = [[]]
        self.cursorLineIndex = 0
        self.cursorColumn = 0

        append(text)
    }

    mutating func append(_ output: String) {
        guard !output.isEmpty else {
            return
        }

        let normalizedOutput = output.replacingOccurrences(of: "\r\n", with: "\n")
        for character in normalizedOutput {
            process(character)
        }
        truncateIfNeeded()
    }

    mutating func clear() {
        lines = [[]]
        cursorLineIndex = 0
        cursorColumn = 0
        parserState = .normal
        carriageReturnPending = false
    }

    private mutating func process(_ character: Character) {
        switch parserState {
        case .normal:
            processVisible(character)
        case .escape:
            processEscape(character)
        case .csi(let parameters):
            processCSI(character, parameters: parameters)
        case .osc:
            processOSC(character)
        case .oscEscape:
            processOSCEscape(character)
        }
    }

    private mutating func processVisible(_ character: Character) {
        switch character {
        case "\u{1B}":
            parserState = .escape
        case "\r":
            cursorColumn = 0
            carriageReturnPending = true
        case "\n":
            lineFeed()
        case "\u{08}", "\u{7F}":
            backspace()
        case "\t":
            writeTab()
        case "\u{0C}":
            clearScreen()
        default:
            guard !isIgnoredControl(character) else {
                return
            }

            write(character)
        }
    }

    private mutating func processEscape(_ character: Character) {
        switch character {
        case "[":
            parserState = .csi("")
        case "]":
            parserState = .osc
        case "c":
            clearScreen()
            parserState = .normal
        case "\u{1B}":
            parserState = .escape
        default:
            parserState = .normal
        }
    }

    private mutating func processCSI(_ character: Character, parameters: String) {
        guard let scalar = singleScalar(from: character) else {
            parserState = .normal
            return
        }

        if isCSIFinalByte(scalar) {
            applyCSI(parameters: parameters, final: character)
            parserState = .normal
            return
        }

        guard parameters.count < 64 else {
            parserState = .normal
            return
        }

        parserState = .csi(parameters + String(character))
    }

    private mutating func processOSC(_ character: Character) {
        switch character {
        case "\u{07}":
            parserState = .normal
        case "\u{1B}":
            parserState = .oscEscape
        default:
            break
        }
    }

    private mutating func processOSCEscape(_ character: Character) {
        switch character {
        case "\\":
            parserState = .normal
        case "\u{1B}":
            parserState = .oscEscape
        default:
            parserState = .osc
        }
    }

    private mutating func applyCSI(parameters: String, final: Character) {
        switch final {
        case "A":
            moveCursorVertically(by: -parameterValue(parameters, at: 0, defaultValue: 1))
        case "B":
            moveCursorVertically(by: parameterValue(parameters, at: 0, defaultValue: 1))
        case "C":
            cursorColumn += parameterValue(parameters, at: 0, defaultValue: 1)
            carriageReturnPending = false
        case "D":
            cursorColumn = max(0, cursorColumn - parameterValue(parameters, at: 0, defaultValue: 1))
            carriageReturnPending = false
        case "G":
            cursorColumn = max(0, parameterValue(parameters, at: 0, defaultValue: 1) - 1)
            carriageReturnPending = false
        case "H", "f":
            moveCursor(toRow: parameterValue(parameters, at: 0, defaultValue: 1),
                       column: parameterValue(parameters, at: 1, defaultValue: 1))
        case "J":
            clearScreen(parameters: parameters)
        case "K":
            clearLine(parameters: parameters)
        default:
            break
        }
    }

    private mutating func write(_ character: Character) {
        beginVisibleWrite()
        ensureCursorLine()

        if cursorColumn > lines[cursorLineIndex].count {
            lines[cursorLineIndex].append(contentsOf: Array(repeating: " ", count: cursorColumn - lines[cursorLineIndex].count))
        }

        if cursorColumn < lines[cursorLineIndex].count {
            lines[cursorLineIndex][cursorColumn] = character
        } else {
            lines[cursorLineIndex].append(character)
        }
        cursorColumn += 1
    }

    private mutating func writeTab() {
        let nextTabStop = ((cursorColumn / 8) + 1) * 8
        repeat {
            write(" ")
        } while cursorColumn < nextTabStop
    }

    private mutating func lineFeed() {
        carriageReturnPending = false

        if cursorLineIndex == lines.count - 1 {
            lines.append([])
        }
        cursorLineIndex = min(cursorLineIndex + 1, lines.count - 1)
        cursorColumn = 0
    }

    private mutating func backspace() {
        carriageReturnPending = false
        guard cursorColumn > 0 else {
            return
        }

        cursorColumn -= 1
        guard cursorColumn < lines[cursorLineIndex].count else {
            return
        }

        lines[cursorLineIndex].remove(at: cursorColumn)
    }

    private mutating func beginVisibleWrite() {
        guard carriageReturnPending else {
            return
        }

        lines[cursorLineIndex].removeAll(keepingCapacity: true)
        cursorColumn = 0
        carriageReturnPending = false
    }

    private mutating func clearLine(parameters: String) {
        carriageReturnPending = false
        ensureCursorLine()

        switch parameterValue(parameters, at: 0, defaultValue: 0) {
        case 1:
            let endIndex = min(cursorColumn, lines[cursorLineIndex].count)
            lines[cursorLineIndex].removeSubrange(0..<endIndex)
            cursorColumn = 0
        case 2:
            lines[cursorLineIndex].removeAll(keepingCapacity: true)
            cursorColumn = 0
        default:
            guard cursorColumn < lines[cursorLineIndex].count else {
                return
            }
            lines[cursorLineIndex].removeSubrange(cursorColumn..<lines[cursorLineIndex].count)
        }
    }

    private mutating func clearScreen(parameters: String) {
        switch parameterValue(parameters, at: 0, defaultValue: 0) {
        case 1:
            lines.removeSubrange(0...cursorLineIndex)
            lines.insert([], at: 0)
            cursorLineIndex = 0
            cursorColumn = 0
        default:
            clearScreen()
        }
    }

    private mutating func clearScreen() {
        lines = [[]]
        cursorLineIndex = 0
        cursorColumn = 0
        carriageReturnPending = false
    }

    private mutating func moveCursorVertically(by offset: Int) {
        ensureCursorLine()
        cursorLineIndex = min(max(0, cursorLineIndex + offset), lines.count - 1)
        cursorColumn = min(cursorColumn, lines[cursorLineIndex].count)
        carriageReturnPending = false
    }

    private mutating func moveCursor(toRow row: Int, column: Int) {
        let targetLineIndex = max(0, row - 1)
        while lines.count <= targetLineIndex {
            lines.append([])
        }
        cursorLineIndex = targetLineIndex
        cursorColumn = max(0, column - 1)
        carriageReturnPending = false
    }

    private mutating func ensureCursorLine() {
        if lines.isEmpty {
            lines = [[]]
            cursorLineIndex = 0
        }

        while lines.count <= cursorLineIndex {
            lines.append([])
        }
    }

    private mutating func truncateIfNeeded() {
        if maximumCharacterCount == 0 {
            clear()
            return
        }

        while text.count > maximumCharacterCount {
            if lines.count > 1 {
                lines.removeFirst()
                cursorLineIndex = max(0, cursorLineIndex - 1)
            } else {
                let overflow = lines[0].count - maximumCharacterCount
                guard overflow > 0 else {
                    break
                }
                lines[0].removeFirst(overflow)
                cursorColumn = max(0, cursorColumn - overflow)
            }
        }

        ensureCursorLine()
        cursorLineIndex = min(cursorLineIndex, lines.count - 1)
        cursorColumn = min(cursorColumn, lines[cursorLineIndex].count)
    }

    private func parameterValue(_ parameters: String, at index: Int, defaultValue: Int) -> Int {
        let values = parameters.split(separator: ";", omittingEmptySubsequences: false)
        guard values.indices.contains(index) else {
            return defaultValue
        }

        let value = values[index].filter { $0.isNumber || $0 == "-" }
        return Int(value) ?? defaultValue
    }

    private func isIgnoredControl(_ character: Character) -> Bool {
        guard let scalar = singleScalar(from: character) else {
            return false
        }

        return scalar.value < 0x20 || scalar.value == 0x7F
    }

    private func singleScalar(from character: Character) -> UnicodeScalar? {
        guard character.unicodeScalars.count == 1 else {
            return nil
        }

        return character.unicodeScalars.first
    }

    private func isCSIFinalByte(_ scalar: UnicodeScalar) -> Bool {
        (0x40...0x7E).contains(Int(scalar.value))
    }

    private enum ParserState: Equatable {
        case normal
        case escape
        case csi(String)
        case osc
        case oscEscape
    }
}
