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
    case indexed(Int)
    case rgb(red: Int, green: Int, blue: Int)
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
    private var savedCursor: CursorSnapshot?
    private var currentStyle = TerminalTextStyle.default
    private var g0CharacterSet = TerminalGraphicSet.ascii
    private var g1CharacterSet = TerminalGraphicSet.ascii
    private var usesG1CharacterSet = false
    private var screenColumns: Int
    private var screenRows: Int
    private var scrollRegionTop = 0
    private var scrollRegionBottom: Int

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

    var gridSnapshot: TerminalGridSnapshot {
        TerminalGridSnapshot(
            lines: lines.map { line in
                TerminalGridLine(
                    cells: line.map { cell in
                        TerminalGridCell(
                            text: String(cell.character),
                            width: cell.width,
                            style: cell.style
                        )
                    }
                )
            }
        )
    }

    init(
        text: String = "",
        maximumCharacterCount: Int = TerminalDisplayBuffer.defaultMaximumCharacterCount,
        columns: Int = 80,
        rows: Int = 24
    ) {
        self.maximumCharacterCount = max(0, maximumCharacterCount)
        self.lines = [[]]
        self.cursorLineIndex = 0
        self.cursorColumn = 0
        self.screenColumns = max(1, columns)
        self.screenRows = max(1, rows)
        self.scrollRegionBottom = max(0, rows - 1)

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

    mutating func resize(columns: Int, rows: Int) {
        screenColumns = max(1, columns)
        screenRows = max(1, rows)
        scrollRegionTop = min(scrollRegionTop, screenRows - 1)
        scrollRegionBottom = min(max(scrollRegionTop, scrollRegionBottom), screenRows - 1)

        if isUsingAlternateScreen {
            ensureScreenRows()
            cursorLineIndex = min(cursorLineIndex, screenRows - 1)
            cursorColumn = min(cursorColumn, screenColumns - 1)
        }
    }

    mutating func clear() {
        lines = [[]]
        cursorLineIndex = 0
        cursorColumn = 0
        parserState = .normal
        carriageReturnPending = false
        primaryScreenSnapshot = nil
        savedCursor = nil
        currentStyle = .default
        g0CharacterSet = .ascii
        g1CharacterSet = .ascii
        usesG1CharacterSet = false
        resetScrollRegion()
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
        case .characterSetSelection(let slot):
            processCharacterSetSelection(character, slot: slot)
        case .stringControl:
            processStringControl(character)
        case .stringControlEscape:
            processStringControlEscape(character)
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
        case "\u{0E}":
            usesG1CharacterSet = true
            carriageReturnPending = false
        case "\u{0F}":
            usesG1CharacterSet = false
            carriageReturnPending = false
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
        case "P", "^", "_", "X":
            parserState = .stringControl
        case "(":
            parserState = .characterSetSelection(.g0)
        case ")":
            parserState = .characterSetSelection(.g1)
        case "*", "+":
            parserState = .characterSetSelection(.ignored)
        case "7":
            saveCursor()
            parserState = .normal
        case "8":
            restoreCursor()
            parserState = .normal
        case "D":
            index()
            parserState = .normal
        case "E":
            nextLine()
            parserState = .normal
        case "M":
            reverseIndex()
            parserState = .normal
        case "c":
            resetTerminalState()
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

    private mutating func processCharacterSetSelection(_ character: Character, slot: CharacterSetSlot) {
        let graphicSet: TerminalGraphicSet
        switch character {
        case "0":
            graphicSet = .decSpecialGraphics
        default:
            graphicSet = .ascii
        }

        switch slot {
        case .g0:
            g0CharacterSet = graphicSet
        case .g1:
            g1CharacterSet = graphicSet
        case .ignored:
            break
        }

        parserState = .normal
    }

    private mutating func processStringControl(_ character: Character) {
        switch character {
        case "\u{07}":
            parserState = .normal
        case "\u{1B}":
            parserState = .stringControlEscape
        default:
            break
        }
    }

    private mutating func processStringControlEscape(_ character: Character) {
        switch character {
        case "\\":
            parserState = .normal
        case "\u{1B}":
            parserState = .stringControlEscape
        default:
            parserState = .stringControl
        }
    }

    private mutating func applyCSI(parameters: String, final: Character) {
        switch final {
        case "A":
            moveCursorVertically(by: -parameterValue(parameters, at: 0, defaultValue: 1))
        case "B":
            moveCursorVertically(by: parameterValue(parameters, at: 0, defaultValue: 1))
        case "C":
            cursorColumn = min(screenColumns - 1, cursorColumn + parameterValue(parameters, at: 0, defaultValue: 1))
            carriageReturnPending = false
        case "D":
            cursorColumn = max(0, cursorColumn - parameterValue(parameters, at: 0, defaultValue: 1))
            carriageReturnPending = false
        case "E":
            moveCursorVertically(by: parameterValue(parameters, at: 0, defaultValue: 1))
            cursorColumn = 0
        case "F":
            moveCursorVertically(by: -parameterValue(parameters, at: 0, defaultValue: 1))
            cursorColumn = 0
        case "G":
            cursorColumn = min(screenColumns - 1, max(0, parameterValue(parameters, at: 0, defaultValue: 1) - 1))
            carriageReturnPending = false
        case "H", "f":
            moveCursor(toRow: parameterValue(parameters, at: 0, defaultValue: 1),
                       column: parameterValue(parameters, at: 1, defaultValue: 1))
        case "d":
            moveCursor(toRow: parameterValue(parameters, at: 0, defaultValue: 1), column: cursorColumn + 1)
        case "J":
            clearScreen(parameters: parameters)
        case "K":
            clearLine(parameters: parameters)
        case "L":
            insertLines(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "M":
            deleteLines(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "P":
            deleteCharacters(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "S":
            scrollUp(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "T":
            scrollDown(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "X":
            eraseCharacters(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "@":
            insertBlankCharacters(count: parameterValue(parameters, at: 0, defaultValue: 1))
        case "m":
            applySGR(parameters: parameters)
        case "r":
            setScrollRegion(parameters: parameters)
        case "s":
            saveCursor()
        case "u":
            restoreCursor()
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

        if cursorColumn >= screenColumns {
            lineFeed(resetColumn: true)
            ensureCursorLine()
        }

        let visibleCharacter = mappedCharacter(character)
        let cell = DisplayCell(
            character: visibleCharacter,
            width: min(displayWidth(of: visibleCharacter), screenColumns),
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
        lineFeed(resetColumn: true)
    }

    private mutating func lineFeed(resetColumn: Bool) {
        carriageReturnPending = false

        if isUsingAlternateScreen {
            ensureScreenRows()
            if cursorLineIndex >= scrollRegionBottom {
                scrollUp(count: 1, top: scrollRegionTop, bottom: scrollRegionBottom)
            } else {
                cursorLineIndex = min(cursorLineIndex + 1, screenRows - 1)
            }
        } else {
            if cursorLineIndex == lines.count - 1 {
                lines.append([])
            }
            cursorLineIndex = min(cursorLineIndex + 1, lines.count - 1)
        }

        if resetColumn {
            cursorColumn = 0
        }
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
            if isUsingAlternateScreen {
                for lineIndex in nextLineIndex..<lines.count {
                    lines[lineIndex].removeAll(keepingCapacity: true)
                }
            } else {
                lines.removeSubrange(nextLineIndex..<lines.count)
            }
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
        if hasAnyMode([47, 1047, 1049], in: parameters) {
            if enabled {
                enterAlternateScreen()
            } else {
                leaveAlternateScreen()
            }
        } else if hasMode(1048, in: parameters) {
            if enabled {
                saveCursor()
            } else {
                restoreCursor()
            }
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
            currentStyle: currentStyle,
            savedCursor: savedCursor,
            g0CharacterSet: g0CharacterSet,
            g1CharacterSet: g1CharacterSet,
            usesG1CharacterSet: usesG1CharacterSet,
            scrollRegionTop: scrollRegionTop,
            scrollRegionBottom: scrollRegionBottom
        )
        clearScreen()
        resetScrollRegion()
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
        savedCursor = primaryScreenSnapshot.savedCursor
        g0CharacterSet = primaryScreenSnapshot.g0CharacterSet
        g1CharacterSet = primaryScreenSnapshot.g1CharacterSet
        usesG1CharacterSet = primaryScreenSnapshot.usesG1CharacterSet
        scrollRegionTop = primaryScreenSnapshot.scrollRegionTop
        scrollRegionBottom = primaryScreenSnapshot.scrollRegionBottom
        self.primaryScreenSnapshot = nil
        ensureCursorLine()
    }

    private mutating func saveCursor() {
        savedCursor = CursorSnapshot(
            cursorLineIndex: cursorLineIndex,
            cursorColumn: cursorColumn,
            currentStyle: currentStyle,
            g0CharacterSet: g0CharacterSet,
            g1CharacterSet: g1CharacterSet,
            usesG1CharacterSet: usesG1CharacterSet
        )
    }

    private mutating func restoreCursor() {
        guard let savedCursor else {
            return
        }

        cursorLineIndex = max(0, min(savedCursor.cursorLineIndex, max(0, lines.count - 1)))
        cursorColumn = max(0, min(savedCursor.cursorColumn, screenColumns - 1))
        currentStyle = savedCursor.currentStyle
        g0CharacterSet = savedCursor.g0CharacterSet
        g1CharacterSet = savedCursor.g1CharacterSet
        usesG1CharacterSet = savedCursor.usesG1CharacterSet
        carriageReturnPending = false
        ensureCursorLine()
    }

    private mutating func index() {
        lineFeed(resetColumn: false)
    }

    private mutating func nextLine() {
        lineFeed(resetColumn: true)
    }

    private mutating func reverseIndex() {
        carriageReturnPending = false

        if isUsingAlternateScreen {
            ensureScreenRows()
            if cursorLineIndex <= scrollRegionTop {
                scrollDown(count: 1, top: scrollRegionTop, bottom: scrollRegionBottom)
            } else {
                cursorLineIndex = max(0, cursorLineIndex - 1)
            }
        } else {
            cursorLineIndex = max(0, cursorLineIndex - 1)
        }
    }

    private mutating func resetTerminalState() {
        primaryScreenSnapshot = nil
        savedCursor = nil
        currentStyle = .default
        g0CharacterSet = .ascii
        g1CharacterSet = .ascii
        usesG1CharacterSet = false
        resetScrollRegion()
        clearScreen()
    }

    private mutating func moveCursorVertically(by offset: Int) {
        ensureCursorLine()
        if isUsingAlternateScreen {
            ensureScreenRows()
        }

        cursorLineIndex = min(max(0, cursorLineIndex + offset), lines.count - 1)
        cursorColumn = min(cursorColumn, displayWidth(of: lines[cursorLineIndex]))
        carriageReturnPending = false
    }

    private mutating func moveCursor(toRow row: Int, column: Int) {
        let targetLineIndex = isUsingAlternateScreen
            ? min(max(0, row - 1), screenRows - 1)
            : max(0, row - 1)
        while lines.count <= targetLineIndex {
            lines.append([])
        }
        cursorLineIndex = targetLineIndex
        cursorColumn = min(screenColumns - 1, max(0, column - 1))
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

    private mutating func ensureScreenRows() {
        guard isUsingAlternateScreen else {
            return
        }

        while lines.count < screenRows {
            lines.append([])
        }

        if lines.count > screenRows {
            lines.removeSubrange(screenRows..<lines.count)
        }
    }

    private mutating func setScrollRegion(parameters: String) {
        let top = max(1, parameterValue(parameters, at: 0, defaultValue: 1))
        let bottom = min(screenRows, parameterValue(parameters, at: 1, defaultValue: screenRows))

        guard top < bottom else {
            resetScrollRegion()
            moveCursor(toRow: 1, column: 1)
            return
        }

        scrollRegionTop = top - 1
        scrollRegionBottom = bottom - 1
        moveCursor(toRow: 1, column: 1)
    }

    private mutating func resetScrollRegion() {
        scrollRegionTop = 0
        scrollRegionBottom = max(0, screenRows - 1)
    }

    private mutating func insertBlankCharacters(count: Int) {
        guard count > 0 else {
            return
        }

        ensureCursorLine()
        padCursorLine(to: cursorColumn)
        let line = paddedLineToScreenWidth(lines[cursorLineIndex])
        let prefix = prefixPreservingColumns(in: line, before: cursorColumn)
        let suffix = suffixPreservingColumns(in: line, from: cursorColumn)
        lines[cursorLineIndex] = trimToScreenWidth(prefix + spaceCells(count: count) + suffix)
    }

    private mutating func deleteCharacters(count: Int) {
        guard count > 0 else {
            return
        }

        ensureCursorLine()
        let line = paddedLineToScreenWidth(lines[cursorLineIndex])
        let prefix = prefixPreservingColumns(in: line, before: cursorColumn)
        let suffix = suffixPreservingColumns(in: line, from: cursorColumn + count)
        lines[cursorLineIndex] = trimToScreenWidth(prefix + suffix + spaceCells(count: count))
    }

    private mutating func eraseCharacters(count: Int) {
        guard count > 0 else {
            return
        }

        ensureCursorLine()
        padCursorLine(to: cursorColumn)
        let eraseCount = min(count, screenColumns - cursorColumn)
        lines[cursorLineIndex] = replacingColumns(
            in: paddedLineToScreenWidth(lines[cursorLineIndex]),
            range: cursorColumn..<(cursorColumn + eraseCount),
            with: spaceCells(count: eraseCount)
        )
    }

    private mutating func insertLines(count: Int) {
        guard count > 0 else {
            return
        }

        ensureScreenRows()
        let top = max(cursorLineIndex, scrollRegionTop)
        guard top <= scrollRegionBottom, lines.indices.contains(top) else {
            return
        }

        let insertCount = min(count, scrollRegionBottom - top + 1)
        lines.insert(contentsOf: Array(repeating: [], count: insertCount), at: top)
        lines.removeSubrange((scrollRegionBottom + 1)..<(scrollRegionBottom + 1 + insertCount))
    }

    private mutating func deleteLines(count: Int) {
        guard count > 0 else {
            return
        }

        ensureScreenRows()
        let top = max(cursorLineIndex, scrollRegionTop)
        guard top <= scrollRegionBottom, lines.indices.contains(top) else {
            return
        }

        let deleteCount = min(count, scrollRegionBottom - top + 1)
        lines.removeSubrange(top..<(top + deleteCount))
        lines.insert(contentsOf: Array(repeating: [], count: deleteCount), at: scrollRegionBottom - deleteCount + 1)
    }

    private mutating func scrollUp(count: Int) {
        scrollUp(count: count, top: scrollRegionTop, bottom: scrollRegionBottom)
    }

    private mutating func scrollUp(count: Int, top: Int, bottom: Int) {
        guard count > 0 else {
            return
        }

        ensureScreenRows()
        guard top <= bottom, lines.indices.contains(top), lines.indices.contains(bottom) else {
            return
        }

        let scrollCount = min(count, bottom - top + 1)
        lines.removeSubrange(top..<(top + scrollCount))
        lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: bottom - scrollCount + 1)
    }

    private mutating func scrollDown(count: Int) {
        scrollDown(count: count, top: scrollRegionTop, bottom: scrollRegionBottom)
    }

    private mutating func scrollDown(count: Int, top: Int, bottom: Int) {
        guard count > 0 else {
            return
        }

        ensureScreenRows()
        guard top <= bottom, lines.indices.contains(top), lines.indices.contains(bottom) else {
            return
        }

        let scrollCount = min(count, bottom - top + 1)
        lines.removeSubrange((bottom - scrollCount + 1)...bottom)
        lines.insert(contentsOf: Array(repeating: [], count: scrollCount), at: top)
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

    private func suffixPreservingColumns(in line: [DisplayCell], from columnStart: Int) -> [DisplayCell] {
        var result: [DisplayCell] = []
        var displayColumn = 0

        for cell in line {
            let nextDisplayColumn = displayColumn + cell.width
            if nextDisplayColumn <= columnStart {
                displayColumn = nextDisplayColumn
                continue
            }

            if displayColumn < columnStart {
                result.append(contentsOf: spaceCells(count: nextDisplayColumn - columnStart))
            } else {
                result.append(cell)
            }
            displayColumn = nextDisplayColumn
        }

        return result
    }

    private func paddedLineToScreenWidth(_ line: [DisplayCell]) -> [DisplayCell] {
        let missingWidth = screenColumns - displayWidth(of: line)
        guard missingWidth > 0 else {
            return line
        }

        return line + spaceCells(count: missingWidth)
    }

    private func trimToScreenWidth(_ line: [DisplayCell]) -> [DisplayCell] {
        prefixPreservingColumns(in: line, before: screenColumns)
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
        TerminalCellWidth.width(of: character)
    }

    private var isUsingAlternateScreen: Bool {
        primaryScreenSnapshot != nil
    }

    private func mappedCharacter(_ character: Character) -> Character {
        let graphicSet = usesG1CharacterSet ? g1CharacterSet : g0CharacterSet
        guard graphicSet == .decSpecialGraphics,
              let scalar = singleScalar(from: character),
              let mappedScalar = TerminalGraphicSet.decSpecialGraphicsMap[scalar] else {
            return character
        }

        return Character(mappedScalar)
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
            case 38:
                if let color = extendedColor(from: values, startIndex: index) {
                    currentStyle.foreground = color.color
                    index = color.endIndex
                }
            case 39:
                currentStyle.foreground = nil
            case 40...47:
                currentStyle.background = .ansi(TerminalANSIColor(rawValue: value - 40) ?? .black)
            case 48:
                if let color = extendedColor(from: values, startIndex: index) {
                    currentStyle.background = color.color
                    index = color.endIndex
                }
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

    private func extendedColor(
        from values: [Int],
        startIndex: Int
    ) -> (color: TerminalTextColor, endIndex: Int)? {
        let modeIndex = startIndex + 1
        guard values.indices.contains(modeIndex) else {
            return nil
        }

        switch values[modeIndex] {
        case 5:
            let colorIndex = startIndex + 2
            guard values.indices.contains(colorIndex) else {
                return nil
            }

            return (.indexed(values[colorIndex]), colorIndex)
        case 2:
            let redIndex = startIndex + 2
            let greenIndex = startIndex + 3
            let blueIndex = startIndex + 4
            guard values.indices.contains(redIndex),
                  values.indices.contains(greenIndex),
                  values.indices.contains(blueIndex) else {
                return nil
            }

            return (
                .rgb(
                    red: clampedColorComponent(values[redIndex]),
                    green: clampedColorComponent(values[greenIndex]),
                    blue: clampedColorComponent(values[blueIndex])
                ),
                blueIndex
            )
        default:
            return nil
        }
    }

    private func clampedColorComponent(_ value: Int) -> Int {
        min(max(value, 0), 255)
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

    private func hasAnyMode(_ modes: [Int], in parameters: String) -> Bool {
        let modeSet = Set(modes)
        return parameters
            .split(separator: ";", omittingEmptySubsequences: false)
            .contains { parameter in
                guard let mode = Int(parameter.filter(\.isNumber)) else {
                    return false
                }

                return modeSet.contains(mode)
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
        case characterSetSelection(CharacterSetSlot)
        case stringControl
        case stringControlEscape
    }

    private enum CharacterSetSlot: Equatable {
        case g0
        case g1
        case ignored
    }

    private enum TerminalGraphicSet: Equatable {
        case ascii
        case decSpecialGraphics

        static let decSpecialGraphicsMap: [UnicodeScalar: UnicodeScalar] = [
            "`": "◆",
            "a": "▒",
            "b": "␉",
            "c": "␌",
            "d": "␍",
            "e": "␊",
            "f": "°",
            "g": "±",
            "h": "␤",
            "i": "␋",
            "j": "┘",
            "k": "┐",
            "l": "┌",
            "m": "└",
            "n": "┼",
            "o": "⎺",
            "p": "⎻",
            "q": "─",
            "r": "⎼",
            "s": "⎽",
            "t": "├",
            "u": "┤",
            "v": "┴",
            "w": "┬",
            "x": "│",
            "y": "≤",
            "z": "≥",
            "{": "π",
            "|": "≠",
            "}": "£",
            "~": "·"
        ]
    }

    private struct ScreenSnapshot: Equatable {
        var lines: [[DisplayCell]]
        var cursorLineIndex: Int
        var cursorColumn: Int
        var carriageReturnPending: Bool
        var currentStyle: TerminalTextStyle
        var savedCursor: CursorSnapshot?
        var g0CharacterSet: TerminalGraphicSet
        var g1CharacterSet: TerminalGraphicSet
        var usesG1CharacterSet: Bool
        var scrollRegionTop: Int
        var scrollRegionBottom: Int
    }

    private struct CursorSnapshot: Equatable {
        var cursorLineIndex: Int
        var cursorColumn: Int
        var currentStyle: TerminalTextStyle
        var g0CharacterSet: TerminalGraphicSet
        var g1CharacterSet: TerminalGraphicSet
        var usesG1CharacterSet: Bool
    }

    private struct DisplayCell: Equatable {
        var character: Character
        var width: Int
        var style: TerminalTextStyle
    }
}
