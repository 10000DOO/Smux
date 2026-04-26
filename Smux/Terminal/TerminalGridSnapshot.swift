import Foundation

nonisolated struct TerminalGridCell: Equatable {
    var text: String
    var width: Int
    var style: TerminalTextStyle

    init(text: String, width: Int = 1, style: TerminalTextStyle = .default) {
        self.text = text
        self.width = max(1, width)
        self.style = style
    }
}

nonisolated struct TerminalGridLine: Equatable {
    var cells: [TerminalGridCell]

    init(cells: [TerminalGridCell] = []) {
        self.cells = cells
    }

    var text: String {
        cells.map(\.text).joined()
    }

    var displayWidth: Int {
        cells.reduce(0) { $0 + $1.width }
    }
}

nonisolated struct TerminalGridSnapshot: Equatable {
    static let empty = TerminalGridSnapshot(lines: [TerminalGridLine()])

    var lines: [TerminalGridLine]

    init(lines: [TerminalGridLine] = [TerminalGridLine()]) {
        self.lines = lines.isEmpty ? [TerminalGridLine()] : lines
    }

    init(text: String, styledRuns: [TerminalStyledTextRun]) {
        self.init(lines: Self.lines(from: text, styledRuns: styledRuns))
    }

    var text: String {
        lines.map(\.text).joined(separator: "\n")
    }

    private static func lines(
        from text: String,
        styledRuns: [TerminalStyledTextRun]
    ) -> [TerminalGridLine] {
        let normalizedRuns = runsMatching(text: text, styledRuns: styledRuns)
        var lines: [TerminalGridLine] = []
        var currentCells: [TerminalGridCell] = []

        for run in normalizedRuns {
            for character in run.text {
                if character == "\n" {
                    lines.append(TerminalGridLine(cells: currentCells))
                    currentCells.removeAll(keepingCapacity: true)
                } else {
                    currentCells.append(
                        TerminalGridCell(
                            text: String(character),
                            width: TerminalCellWidth.width(of: character),
                            style: run.style
                        )
                    )
                }
            }
        }

        lines.append(TerminalGridLine(cells: currentCells))
        return lines
    }

    private static func runsMatching(
        text: String,
        styledRuns: [TerminalStyledTextRun]
    ) -> [TerminalStyledTextRun] {
        guard !styledRuns.isEmpty,
              styledRuns.map(\.text).joined() == text else {
            return [TerminalStyledTextRun(text: text, style: .default)]
        }

        return styledRuns
    }
}
