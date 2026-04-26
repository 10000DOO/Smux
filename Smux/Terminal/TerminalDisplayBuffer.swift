import Foundation

nonisolated struct TerminalStyledTextRun: Equatable {
    var text: String
    var style: TerminalTextStyle
}

nonisolated struct TerminalTextStyle: Equatable {
    static let `default` = TerminalTextStyle()

    var foreground: TerminalTextColor?
    var background: TerminalTextColor?
    var isBold = false
    var isItalic = false
    var isUnderline = false
}

nonisolated enum TerminalTextColor: Equatable {
    case ansi(TerminalANSIColor)
}

nonisolated enum TerminalANSIColor: Int, Equatable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
}

nonisolated struct TerminalDisplayBuffer: Equatable {
    static let defaultMaximumCharacterCount = 200_000

    let maximumCharacterCount: Int

    private var lines: [[DisplayCell]]
    private var cursorLineIndex: Int
    private var cursorColumn: Int
    private var parserState: ParserState = .normal
    private var carriageReturnPending = false
    private var primaryScreenSnapshot: ScreenSnapshot?
    private var currentStyle = TerminalTextStyle.default

    var text: String {
        lines.map { line in String(line.map(\.character)) }.joined(separator: "\n")
    }

    var styledRuns: [TerminalStyledTextRun] {
        var runs: [TerminalStyledTextRun] = []

        for (lineIndex, line) in lines.enumerated() {
            append(line: line, to: &runs)
            if lineIndex < lines.index(before: lines.endIndex) {
                append(character: "\n", style: .default, to: &runs)
            }
        }

        return runs
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
        primaryScreenSnapshot = nil
        currentStyle = .default
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
        case "m":
            applySGR(parameters: parameters)
        case "h":
            setPrivateMode(parameters: parameters, enabled: true)
        case "l":
            setPrivateMode(parameters: parameters, enabled: false)
        default:
            break
        }
    }

    private mutating func write(_ character: Character) {
        beginVisibleWrite()
        ensureCursorLine()

        let cell = DisplayCell(
            character: character,
            width: displayWidth(of: character),
            style: currentStyle
        )
        let writeRange = cursorColumn..<(cursorColumn + cell.width)

        padCursorLine(to: cursorColumn)
        lines[cursorLineIndex] = replacingColumns(
            in: lines[cursorLineIndex],
            range: writeRange,
            with: [cell]
        )
        cursorColumn += cell.width
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
        ensureCursorLine()

        var displayColumn = 0
        for (cellIndex, cell) in lines[cursorLineIndex].enumerated() {
            let nextDisplayColumn = displayColumn + cell.width
            if nextDisplayColumn >= cursorColumn {
                cursorColumn = displayColumn
                lines[cursorLineIndex].remove(at: cellIndex)
                return
            }
            displayColumn = nextDisplayColumn
        }

        cursorColumn = max(0, cursorColumn - 1)
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
            replaceFromStartThroughCursorWithSpaces(lineIndex: cursorLineIndex)
        case 2:
            lines[cursorLineIndex].removeAll(keepingCapacity: true)
        default:
            removeFromCursorToEnd(lineIndex: cursorLineIndex)
        }
    }

    private mutating func clearScreen(parameters: String) {
        switch parameterValue(parameters, at: 0, defaultValue: 0) {
        case 0:
            clearFromCursorToEndOfScreen()
        case 1:
            clearFromStartOfScreenToCursor()
        case 2, 3:
            clearScreen()
        default:
            clearFromCursorToEndOfScreen()
        }
    }

    private mutating func clearScreen() {
        lines = [[]]
        cursorLineIndex = 0
        cursorColumn = 0
        carriageReturnPending = false
    }

    private mutating func clearFromCursorToEndOfScreen() {
        carriageReturnPending = false
        ensureCursorLine()

        removeFromCursorToEnd(lineIndex: cursorLineIndex)

        let nextLineIndex = cursorLineIndex + 1
        if nextLineIndex < lines.count {
            lines.removeSubrange(nextLineIndex..<lines.count)
        }
    }

    private mutating func clearFromStartOfScreenToCursor() {
        carriageReturnPending = false
        ensureCursorLine()

        if cursorLineIndex > 0 {
            for lineIndex in 0..<cursorLineIndex {
                lines[lineIndex].removeAll(keepingCapacity: true)
            }
        }

        replaceFromStartThroughCursorWithSpaces(lineIndex: cursorLineIndex)
    }

    private mutating func removeFromCursorToEnd(lineIndex: Int) {
        guard lines.indices.contains(lineIndex) else {
            return
        }

        lines[lineIndex] = prefixPreservingColumns(
            in: lines[lineIndex],
            before: cursorColumn
        )
    }

    private mutating func replaceFromStartThroughCursorWithSpaces(lineIndex: Int) {
        guard lines.indices.contains(lineIndex) else {
            return
        }

        let prefix = prefixCoveringColumns(
            in: lines[lineIndex],
            upTo: cursorColumn + 1
        )
        lines[lineIndex] = spaceCells(count: prefix.width) + Array(lines[lineIndex].dropFirst(prefix.endIndex))
    }

    private mutating func setPrivateMode(parameters: String, enabled: Bool) {
        guard hasMode(1049, in: parameters) else {
            return
        }

        if enabled {
            enterAlternateScreen()
        } else {
            leaveAlternateScreen()
        }
    }

    private mutating func enterAlternateScreen() {
        guard primaryScreenSnapshot == nil else {
            clearScreen()
            return
        }

        primaryScreenSnapshot = ScreenSnapshot(
            lines: lines,
            cursorLineIndex: cursorLineIndex,
            cursorColumn: cursorColumn,
            carriageReturnPending: carriageReturnPending,
            currentStyle: currentStyle
        )
        clearScreen()
    }

    private mutating func leaveAlternateScreen() {
        guard let primaryScreenSnapshot else {
            return
        }

        lines = primaryScreenSnapshot.lines
        cursorLineIndex = primaryScreenSnapshot.cursorLineIndex
        cursorColumn = primaryScreenSnapshot.cursorColumn
        carriageReturnPending = primaryScreenSnapshot.carriageReturnPending
        currentStyle = primaryScreenSnapshot.currentStyle
        self.primaryScreenSnapshot = nil
        ensureCursorLine()
    }

    private mutating func moveCursorVertically(by offset: Int) {
        ensureCursorLine()
        cursorLineIndex = min(max(0, cursorLineIndex + offset), lines.count - 1)
        cursorColumn = min(cursorColumn, displayWidth(of: lines[cursorLineIndex]))
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

        var characterCount = displayCharacterCount()
        guard characterCount > maximumCharacterCount else {
            return
        }

        var removedLineCount = 0
        while characterCount > maximumCharacterCount,
              lines.count - removedLineCount > 1 {
            characterCount -= lines[removedLineCount].count + 1
            removedLineCount += 1
        }

        if removedLineCount > 0 {
            lines.removeFirst(removedLineCount)
            cursorLineIndex = max(0, cursorLineIndex - removedLineCount)
        }

        if characterCount > maximumCharacterCount {
            let removedCellCount = min(characterCount - maximumCharacterCount, lines[0].count)
            let removedWidth = lines[0].prefix(removedCellCount).reduce(0) { width, cell in
                width + cell.width
            }

            lines[0].removeFirst(removedCellCount)
            cursorColumn = max(0, cursorColumn - removedWidth)
        }

        ensureCursorLine()
        cursorLineIndex = min(cursorLineIndex, lines.count - 1)
        cursorColumn = min(cursorColumn, displayWidth(of: lines[cursorLineIndex]))
    }

    private func displayCharacterCount() -> Int {
        lines.reduce(max(0, lines.count - 1)) { count, line in
            count + line.count
        }
    }

    private mutating func padCursorLine(to column: Int) {
        let missingWidth = column - displayWidth(of: lines[cursorLineIndex])
        guard missingWidth > 0 else {
            return
        }

        lines[cursorLineIndex].append(contentsOf: spaceCells(count: missingWidth))
    }

    private func replacingColumns(
        in line: [DisplayCell],
        range: Range<Int>,
        with replacement: [DisplayCell]
    ) -> [DisplayCell] {
        var result: [DisplayCell] = []
        var insertedReplacement = false
        var displayColumn = 0

        for cell in line {
            let nextDisplayColumn = displayColumn + cell.width

            if nextDisplayColumn <= range.lowerBound {
                result.append(cell)
            } else if displayColumn >= range.upperBound {
                if !insertedReplacement {
                    result.append(contentsOf: replacement)
                    insertedReplacement = true
                }
                result.append(cell)
            } else {
                if displayColumn < range.lowerBound {
                    result.append(contentsOf: spaceCells(count: range.lowerBound - displayColumn))
                }
                if !insertedReplacement {
                    result.append(contentsOf: replacement)
                    insertedReplacement = true
                }
                if nextDisplayColumn > range.upperBound {
                    result.append(contentsOf: spaceCells(count: nextDisplayColumn - range.upperBound))
                }
            }

            displayColumn = nextDisplayColumn
        }

        if !insertedReplacement {
            result.append(contentsOf: replacement)
        }

        return result
    }

    private func prefixPreservingColumns(in line: [DisplayCell], before columnLimit: Int) -> [DisplayCell] {
        var result: [DisplayCell] = []
        var displayColumn = 0

        for cell in line {
            let nextDisplayColumn = displayColumn + cell.width
            if nextDisplayColumn <= columnLimit {
                result.append(cell)
            } else {
                if displayColumn < columnLimit {
                    result.append(contentsOf: spaceCells(count: columnLimit - displayColumn))
                }
                break
            }
            displayColumn = nextDisplayColumn
        }

        return result
    }

    private func prefixCoveringColumns(in line: [DisplayCell], upTo columnLimit: Int) -> (width: Int, endIndex: Int) {
        guard columnLimit > 0 else {
            return (0, 0)
        }

        var displayWidth = 0
        for (cellIndex, cell) in line.enumerated() {
            guard displayWidth < columnLimit else {
                return (displayWidth, cellIndex)
            }

            displayWidth += cell.width
        }

        return (displayWidth, line.count)
    }

    private func spaceCells(count: Int) -> [DisplayCell] {
        guard count > 0 else {
            return []
        }

        return Array(
            repeating: DisplayCell(character: " ", width: 1, style: .default),
            count: count
        )
    }

    private func displayWidth(of line: [DisplayCell]) -> Int {
        line.reduce(0) { $0 + $1.width }
    }

    private func displayWidth(of character: Character) -> Int {
        character.unicodeScalars.contains(where: isWideScalar) ? 2 : 1
    }

    private mutating func applySGR(parameters: String) {
        let values = sgrValues(from: parameters)
        var index = 0

        while index < values.count {
            let value = values[index]

            switch value {
            case 0:
                currentStyle = .default
            case 1:
                currentStyle.isBold = true
            case 3:
                currentStyle.isItalic = true
            case 4:
                currentStyle.isUnderline = true
            case 22:
                currentStyle.isBold = false
            case 23:
                currentStyle.isItalic = false
            case 24:
                currentStyle.isUnderline = false
            case 30...37:
                currentStyle.foreground = .ansi(TerminalANSIColor(rawValue: value - 30) ?? .white)
            case 39:
                currentStyle.foreground = nil
            case 40...47:
                currentStyle.background = .ansi(TerminalANSIColor(rawValue: value - 40) ?? .black)
            case 49:
                currentStyle.background = nil
            case 90...97:
                currentStyle.foreground = .ansi(TerminalANSIColor(rawValue: value - 90 + 8) ?? .brightWhite)
            case 100...107:
                currentStyle.background = .ansi(TerminalANSIColor(rawValue: value - 100 + 8) ?? .brightBlack)
            default:
                break
            }

            index += 1
        }
    }

    private func sgrValues(from parameters: String) -> [Int] {
        guard !parameters.isEmpty else {
            return [0]
        }

        let values = parameters
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { parameter -> Int in
                guard !parameter.isEmpty else {
                    return 0
                }

                return Int(parameter) ?? 0
            }

        return values.isEmpty ? [0] : values
    }

    private func parameterValue(_ parameters: String, at index: Int, defaultValue: Int) -> Int {
        let values = parameters.split(separator: ";", omittingEmptySubsequences: false)
        guard values.indices.contains(index) else {
            return defaultValue
        }

        let value = values[index].filter { $0.isNumber || $0 == "-" }
        return Int(value) ?? defaultValue
    }

    private func hasMode(_ mode: Int, in parameters: String) -> Bool {
        parameters
            .split(separator: ";", omittingEmptySubsequences: false)
            .contains { parameter in
                Int(parameter.filter(\.isNumber)) == mode
            }
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

    private func isWideScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F000...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    private func append(line: [DisplayCell], to runs: inout [TerminalStyledTextRun]) {
        for cell in line {
            append(character: cell.character, style: cell.style, to: &runs)
        }
    }

    private func append(
        character: Character,
        style: TerminalTextStyle,
        to runs: inout [TerminalStyledTextRun]
    ) {
        if let lastRun = runs.last, lastRun.style == style {
            runs[runs.index(before: runs.endIndex)].text.append(character)
        } else {
            runs.append(TerminalStyledTextRun(text: String(character), style: style))
        }
    }

    private enum ParserState: Equatable {
        case normal
        case escape
        case csi(String)
        case osc
        case oscEscape
    }

    private struct ScreenSnapshot: Equatable {
        var lines: [[DisplayCell]]
        var cursorLineIndex: Int
        var cursorColumn: Int
        var carriageReturnPending: Bool
        var currentStyle: TerminalTextStyle
    }

    private struct DisplayCell: Equatable {
        var character: Character
        var width: Int
        var style: TerminalTextStyle
    }
}
