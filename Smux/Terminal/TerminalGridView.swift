import AppKit

final class TerminalGridView: NSView, NSTextFinderClient, NSTextInputClient {
    var inputHandler: ((String) -> Void)?

    private(set) var snapshot: TerminalGridSnapshot = .empty
    private(set) var terminalAppearance = TerminalAppearance()
    private var typography = TerminalTypography.make(appearance: TerminalAppearance())
    private var terminalMarkedText = ""
    private var terminalMarkedSelectedRange = NSRange(location: 0, length: 0)
    private lazy var terminalInputContext = NSTextInputContext(client: self)
    private lazy var terminalTextFinder: NSTextFinder = {
        let textFinder = NSTextFinder()
        textFinder.client = self
        textFinder.isIncrementalSearchingEnabled = true
        textFinder.incrementalSearchingShouldDimContentView = false
        return textFinder
    }()
    private var selection: TerminalGridSelection?
    private var textFinderSelectedRange = NSRange(location: 0, length: 0)

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var inputContext: NSTextInputContext? {
        terminalInputContext
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        terminalTextFinder.findBarContainer = enclosingScrollView
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let position = gridPosition(for: convert(event.locationInWindow, from: nil))
        selection = TerminalGridSelection(anchor: position, focus: position)
        textFinderSelectedRange = NSRange(location: 0, length: 0)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var selection else {
            return
        }

        selection.focus = gridPosition(for: convert(event.locationInWindow, from: nil))
        self.selection = selection
        textFinderSelectedRange = NSRange(location: 0, length: 0)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = TerminalInputModifiers(event.modifierFlags)
        guard !modifiers.contains(.command) else {
            super.keyDown(with: event)
            return
        }

        guard let key = TerminalInputKey(event: event) else {
            interpretKeyEvents([event])
            return
        }

        switch key {
        case .text:
            interpretKeyEvents([event])
        default:
            if let input = TerminalInputTranslator.input(for: key, modifiers: modifiers) {
                inputHandler?(input)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let input = NSPasteboard.general.string(forType: .string), !input.isEmpty else {
            return
        }

        inputHandler?(input)
    }

    @objc func copy(_ sender: Any?) {
        guard let selectedText = selection?.selectedText(from: snapshot), !selectedText.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        let lastRow = max(0, snapshot.lines.index(before: snapshot.lines.endIndex))
        let lastColumn = snapshot.lines.last?.displayWidth ?? 0
        selection = TerminalGridSelection(
            anchor: TerminalGridPosition(row: 0, column: 0),
            focus: TerminalGridPosition(row: lastRow, column: lastColumn)
        )
        textFinderSelectedRange = NSRange(location: 0, length: textFinderString.length)
        needsDisplay = true
    }

    func update(snapshot: TerminalGridSnapshot, appearance: TerminalAppearance) {
        let nextTypography = TerminalTypography.make(appearance: appearance)
        let didChangeSnapshot = self.snapshot != snapshot
        let shouldRedraw = didChangeSnapshot || terminalAppearance != appearance

        if didChangeSnapshot {
            terminalTextFinder.noteClientStringWillChange()
        }
        self.snapshot = snapshot
        terminalAppearance = appearance
        typography = nextTypography
        layer?.backgroundColor = typography.palette.background.cgColor
        textFinderSelectedRange = clamp(range: textFinderSelectedRange)
        resizeToFitVisibleWidth()

        if shouldRedraw {
            needsDisplay = true
        }
    }

    func shouldFollowTailOnTextUpdate() -> Bool {
        guard let scrollView = enclosingScrollView else {
            return true
        }

        let visibleBounds = scrollView.contentView.bounds
        return TerminalScrollPolicy.shouldFollowTail(
            visibleMaxY: visibleBounds.maxY,
            visibleHeight: visibleBounds.height,
            documentHeight: bounds.height
        )
    }

    func restoreVisibleOrigin(_ origin: NSPoint) {
        guard let scrollView = enclosingScrollView else {
            return
        }

        let contentView = scrollView.contentView
        let y = TerminalScrollPolicy.clampedVisibleOriginY(
            origin.y,
            visibleHeight: contentView.bounds.height,
            documentHeight: bounds.height
        )
        contentView.scroll(to: NSPoint(x: origin.x, y: y))
        scrollView.reflectScrolledClipView(contentView)
    }

    func scrollToEnd() {
        guard let scrollView = enclosingScrollView else {
            return
        }

        let contentView = scrollView.contentView
        let y = TerminalScrollPolicy.clampedVisibleOriginY(
            bounds.height - contentView.bounds.height,
            visibleHeight: contentView.bounds.height,
            documentHeight: bounds.height
        )
        contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(contentView)
    }

    func resizeToFitVisibleWidth() {
        guard let scrollView = enclosingScrollView else {
            return
        }

        let visibleSize = scrollView.contentView.bounds.size
        let nextSize = NSSize(
            width: max(visibleSize.width, requiredContentWidth),
            height: max(visibleSize.height, requiredContentHeight)
        )

        if frame.size != nextSize {
            setFrameSize(nextSize)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        TerminalCellRenderer.draw(
            snapshot: snapshot,
            dirtyRect: dirtyRect,
            typography: typography,
            selection: selection
        )
    }

    private var requiredContentHeight: CGFloat {
        typography.verticalInset + CGFloat(max(1, snapshot.lines.count)) * typography.cellSize.height
    }

    private var requiredContentWidth: CGFloat {
        let maxLineWidth = snapshot.lines.map(\.displayWidth).max() ?? 0
        return typography.horizontalInset + CGFloat(max(1, maxLineWidth)) * typography.cellSize.width
    }

    private func gridPosition(for point: NSPoint) -> TerminalGridPosition {
        let rowHeight = typography.cellSize.height
        let cellWidth = typography.cellSize.width
        let unclampedRow = Int((point.y - typography.textInsets.height) / rowHeight)
        let row = min(max(0, unclampedRow), max(0, snapshot.lines.count - 1))
        let maxColumn = snapshot.lines.indices.contains(row) ? snapshot.lines[row].displayWidth : 0
        let unclampedColumn = Int((point.x - typography.textInsets.width) / cellWidth)
        let column = min(max(0, unclampedColumn), maxColumn)
        return TerminalGridPosition(row: row, column: column)
    }

    private var textFinderString: NSString {
        snapshot.text as NSString
    }

    private func textFinderAction(from sender: Any?) -> NSTextFinder.Action? {
        guard let item = sender as? NSValidatedUserInterfaceItem else {
            return nil
        }

        return NSTextFinder.Action(rawValue: item.tag)
    }

    private func setTextFinderSelection(_ range: NSRange) {
        let clampedRange = clamp(range: range)
        textFinderSelectedRange = clampedRange

        guard clampedRange.length > 0 else {
            selection = nil
            needsDisplay = true
            return
        }

        selection = TerminalGridSelection(
            anchor: gridPosition(forCharacterIndex: clampedRange.location),
            focus: gridPosition(forCharacterIndex: clampedRange.location + clampedRange.length)
        )
        scrollRangeToVisible(clampedRange)
        needsDisplay = true
    }

    private func clamp(range: NSRange) -> NSRange {
        let textLength = textFinderString.length
        guard range.location != NSNotFound else {
            return NSRange(location: 0, length: 0)
        }

        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }

    private func gridPosition(forCharacterIndex characterIndex: Int) -> TerminalGridPosition {
        let clampedIndex = min(max(0, characterIndex), textFinderString.length)
        var lineStart = 0

        for (row, line) in snapshot.lines.enumerated() {
            let lineLength = (line.text as NSString).length
            let lineEnd = lineStart + lineLength
            if clampedIndex <= lineEnd {
                return TerminalGridPosition(
                    row: row,
                    column: displayColumn(in: line, utf16Offset: clampedIndex - lineStart)
                )
            }

            lineStart = lineEnd + 1
        }

        let lastRow = max(0, snapshot.lines.index(before: snapshot.lines.endIndex))
        return TerminalGridPosition(
            row: lastRow,
            column: snapshot.lines.last?.displayWidth ?? 0
        )
    }

    private func displayColumn(in line: TerminalGridLine, utf16Offset: Int) -> Int {
        let clampedOffset = max(0, utf16Offset)
        var currentOffset = 0
        var column = 0

        for cell in line.cells {
            if clampedOffset <= currentOffset {
                return column
            }

            let nextOffset = currentOffset + (cell.text as NSString).length
            if clampedOffset < nextOffset {
                return column
            }

            currentOffset = nextOffset
            column += cell.width
        }

        return column
    }

    private func rect(for position: TerminalGridPosition, width: Int) -> NSRect {
        rect(
            row: position.row,
            startColumn: position.column,
            endColumn: position.column + max(1, width)
        )
    }

    private func rect(row: Int, startColumn: Int, endColumn: Int) -> NSRect {
        let rowHeight = typography.cellSize.height
        let cellWidth = typography.cellSize.width
        let safeStartColumn = max(0, startColumn)
        let safeEndColumn = max(safeStartColumn + 1, endColumn)
        return NSRect(
            x: typography.textInsets.width + CGFloat(safeStartColumn) * cellWidth,
            y: typography.textInsets.height + CGFloat(max(0, row)) * rowHeight,
            width: CGFloat(safeEndColumn - safeStartColumn) * cellWidth,
            height: rowHeight
        )
    }

    func insertText(_ insertString: Any, replacementRange: NSRange) {
        terminalMarkedText = ""
        terminalMarkedSelectedRange = NSRange(location: 0, length: 0)

        guard let input = TerminalInputTextExtractor.text(from: insertString), !input.isEmpty else {
            return
        }

        inputHandler?(input)
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        terminalMarkedText = TerminalInputTextExtractor.text(from: string) ?? ""
        terminalMarkedSelectedRange = selectedRange
    }

    func unmarkText() {
        terminalMarkedText = ""
        terminalMarkedSelectedRange = NSRange(location: 0, length: 0)
    }

    func hasMarkedText() -> Bool {
        !terminalMarkedText.isEmpty
    }

    func markedRange() -> NSRange {
        guard hasMarkedText() else {
            return NSRange(location: NSNotFound, length: 0)
        }

        return NSRange(location: 0, length: (terminalMarkedText as NSString).length)
    }

    func selectedRange() -> NSRange {
        terminalMarkedSelectedRange
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        guard let window else {
            return .zero
        }

        let localRect = bounds.isEmpty ? NSRect(origin: .zero, size: NSSize(width: 1, height: 1)) : bounds
        return window.convertToScreen(convert(localRect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    override func doCommand(by selector: Selector) {}

    override func performTextFinderAction(_ sender: Any?) {
        guard let action = textFinderAction(from: sender) else {
            super.performTextFinderAction(sender)
            return
        }

        terminalTextFinder.findBarContainer = enclosingScrollView
        terminalTextFinder.performAction(action)
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(performTextFinderAction(_:)),
              let action = NSTextFinder.Action(rawValue: item.tag) else {
            return true
        }

        return terminalTextFinder.validateAction(action)
    }

    var string: String {
        textFinderString as String
    }

    var isSelectable: Bool {
        true
    }

    var allowsMultipleSelection: Bool {
        false
    }

    var isEditable: Bool {
        false
    }

    var firstSelectedRange: NSRange {
        textFinderSelectedRange
    }

    var selectedRanges: [NSValue] {
        get {
            [NSValue(range: textFinderSelectedRange)]
        }
        set {
            guard let range = newValue.first?.rangeValue else {
                textFinderSelectedRange = NSRange(location: 0, length: 0)
                selection = nil
                needsDisplay = true
                return
            }

            setTextFinderSelection(range)
        }
    }

    var visibleCharacterRanges: [NSValue] {
        [NSValue(range: NSRange(location: 0, length: textFinderString.length))]
    }

    func scrollRangeToVisible(_ range: NSRange) {
        guard let rect = rects(forCharacterRange: range)?.first?.rectValue else {
            return
        }

        scrollToVisible(rect)
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: textFinderString.length)
        return self
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        let clampedRange = clamp(range: range)
        guard clampedRange.length > 0 else {
            let position = gridPosition(forCharacterIndex: clampedRange.location)
            return [NSValue(rect: rect(for: position, width: 1))]
        }

        let start = gridPosition(forCharacterIndex: clampedRange.location)
        let end = gridPosition(forCharacterIndex: clampedRange.location + clampedRange.length)
        let normalized = start <= end ? (start, end) : (end, start)
        let values = (normalized.0.row...normalized.1.row).map { row -> NSValue in
            let lineWidth = snapshot.lines.indices.contains(row) ? snapshot.lines[row].displayWidth : 0
            let startColumn = row == normalized.0.row ? normalized.0.column : 0
            let endColumn = row == normalized.1.row ? normalized.1.column : lineWidth
            return NSValue(rect: rect(
                row: row,
                startColumn: startColumn,
                endColumn: max(startColumn + 1, endColumn)
            ))
        }
        return values
    }

    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard view === self else {
            return
        }

        draw(bounds)
    }
}

enum TerminalPowerlineSymbol: Character {
    case branch = "\u{E0A0}"
    case rightSeparator = "\u{E0B0}"
    case rightThinSeparator = "\u{E0B1}"
    case leftSeparator = "\u{E0B2}"
    case leftThinSeparator = "\u{E0B3}"

    init?(text: String) {
        guard text.count == 1, let character = text.first else {
            return nil
        }

        self.init(rawValue: character)
    }

    func draw(in rect: NSRect, foregroundColor: NSColor) {
        foregroundColor.set()

        switch self {
        case .branch:
            drawBranch(in: rect)
        case .rightSeparator:
            drawRightSeparator(in: rect)
        case .rightThinSeparator:
            drawRightThinSeparator(in: rect)
        case .leftSeparator:
            drawLeftSeparator(in: rect)
        case .leftThinSeparator:
            drawLeftThinSeparator(in: rect)
        }
    }

    private func drawRightSeparator(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        path.fill()
    }

    private func drawRightThinSeparator(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawLeftSeparator(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        path.fill()
    }

    private func drawLeftThinSeparator(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawBranch(in rect: NSRect) {
        let iconRect = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
        let size = min(iconRect.width, iconRect.height)
        let strokeWidth = max(2, size * 0.18)
        let radius = max(1.25, strokeWidth * 0.58)
        let stemX = iconRect.minX + iconRect.width * 0.32
        let topY = iconRect.minY + iconRect.height * 0.13
        let bottomY = iconRect.minY + iconRect.height * 0.87
        let forkY = iconRect.minY + iconRect.height * 0.52
        let branchX = iconRect.minX + iconRect.width * 0.78
        let branchY = iconRect.minY + iconRect.height * 0.30

        let path = NSBezierPath()
        path.move(to: NSPoint(x: stemX, y: topY + radius))
        path.line(to: NSPoint(x: stemX, y: bottomY - radius))
        path.move(to: NSPoint(x: stemX, y: forkY))
        path.curve(
            to: NSPoint(x: branchX - radius, y: branchY),
            controlPoint1: NSPoint(x: stemX + iconRect.width * 0.08, y: forkY),
            controlPoint2: NSPoint(x: branchX - iconRect.width * 0.20, y: branchY)
        )
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        drawCircle(center: NSPoint(x: stemX, y: topY), radius: radius)
        drawCircle(center: NSPoint(x: stemX, y: bottomY), radius: radius)
        drawCircle(center: NSPoint(x: branchX, y: branchY), radius: radius)
    }

    private func drawCircle(center: NSPoint, radius: CGFloat) {
        let rect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        NSBezierPath(ovalIn: rect).fill()
    }
}

enum TerminalCellRenderer {
    static func draw(
        snapshot: TerminalGridSnapshot,
        dirtyRect: NSRect,
        typography: TerminalTypography,
        selection: TerminalGridSelection?
    ) {
        typography.palette.background.setFill()
        dirtyRect.fill()

        let cellWidth = typography.cellSize.width
        let rowHeight = typography.cellSize.height
        let startRow = max(0, Int((dirtyRect.minY - typography.textInsets.height) / rowHeight))
        let endRow = min(
            snapshot.lines.count,
            Int(ceil((dirtyRect.maxY - typography.textInsets.height) / rowHeight)) + 1
        )

        guard startRow < endRow else {
            return
        }

        for row in startRow..<endRow {
            draw(
                line: snapshot.lines[row],
                row: row,
                cellWidth: cellWidth,
                rowHeight: rowHeight,
                dirtyRect: dirtyRect,
                typography: typography,
                selection: selection
            )
        }
    }

    private static func draw(
        line: TerminalGridLine,
        row: Int,
        cellWidth: CGFloat,
        rowHeight: CGFloat,
        dirtyRect: NSRect,
        typography: TerminalTypography,
        selection: TerminalGridSelection?
    ) {
        let visibleRange = visibleCellRange(
            in: line,
            dirtyRect: dirtyRect,
            typography: typography
        )
        var column = line.cells[..<visibleRange.lowerBound].reduce(0) { $0 + $1.width }
        let y = typography.textInsets.height + CGFloat(row) * rowHeight

        for index in visibleRange {
            let cell = line.cells[index]
            let isSelected = selection?.intersects(
                row: row,
                column: column,
                width: cell.width
            ) ?? false
            let cellRect = NSRect(
                x: typography.textInsets.width + CGFloat(column) * cellWidth,
                y: y,
                width: CGFloat(cell.width) * cellWidth,
                height: rowHeight
            )

            if isSelected {
                NSColor.selectedTextBackgroundColor.setFill()
                cellRect.fill()
            } else if let backgroundColor = typography.backgroundColor(for: cell.style) {
                backgroundColor.setFill()
                cellRect.fill()
            }

            drawText(cell, in: cellRect, rowHeight: rowHeight, typography: typography, isSelected: isSelected)
            column += cell.width
        }
    }

    static func visibleCellRange(
        in line: TerminalGridLine,
        dirtyRect: NSRect,
        typography: TerminalTypography
    ) -> Range<Int> {
        var column = 0
        var lowerBound: Int?
        var upperBound = 0

        for (index, cell) in line.cells.enumerated() {
            let cellMinX = typography.textInsets.width + CGFloat(column) * typography.cellSize.width
            let cellMaxX = cellMinX + CGFloat(cell.width) * typography.cellSize.width

            if cellMaxX > dirtyRect.minX && cellMinX < dirtyRect.maxX {
                if lowerBound == nil {
                    lowerBound = index
                }
                upperBound = index + 1
            } else if cellMinX >= dirtyRect.maxX {
                break
            }

            column += cell.width
        }

        guard let lowerBound else {
            return 0..<0
        }

        return lowerBound..<upperBound
    }

    private static func drawText(
        _ cell: TerminalGridCell,
        in rect: NSRect,
        rowHeight: CGFloat,
        typography: TerminalTypography,
        isSelected: Bool
    ) {
        let font = typography.font(for: cell.style)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = rowHeight
        paragraphStyle.maximumLineHeight = rowHeight
        paragraphStyle.lineBreakMode = .byClipping

        let foregroundColor = isSelected ? NSColor.selectedTextColor : typography.foregroundColor(for: cell.style)

        if let symbol = TerminalPowerlineSymbol(text: cell.text) {
            symbol.draw(in: rect, foregroundColor: foregroundColor)
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle,
            .ligature: 0,
            .kern: 0
        ]

        (cell.text as NSString).draw(in: rect, withAttributes: attributes)

        if cell.style.isUnderline {
            typography.foregroundColor(for: cell.style).setStroke()
            let underlineY = rect.minY + rowHeight - 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: underlineY))
            path.line(to: NSPoint(x: rect.maxX, y: underlineY))
            path.lineWidth = 1
            path.stroke()
        }
    }
}

struct TerminalGridPosition: Equatable, Comparable {
    var row: Int
    var column: Int

    static func < (lhs: TerminalGridPosition, rhs: TerminalGridPosition) -> Bool {
        if lhs.row == rhs.row {
            return lhs.column < rhs.column
        }

        return lhs.row < rhs.row
    }
}

struct TerminalGridSelection: Equatable {
    var anchor: TerminalGridPosition
    var focus: TerminalGridPosition

    var isEmpty: Bool {
        anchor == focus
    }

    func intersects(row: Int, column: Int, width: Int) -> Bool {
        guard !isEmpty else {
            return false
        }

        let range = normalizedRange
        guard row >= range.start.row, row <= range.end.row else {
            return false
        }

        let selectedStart = row == range.start.row ? range.start.column : 0
        let selectedEnd = row == range.end.row ? range.end.column : Int.max
        return column < selectedEnd && column + width > selectedStart
    }

    func selectedText(from snapshot: TerminalGridSnapshot) -> String? {
        guard !isEmpty else {
            return nil
        }

        let range = normalizedRange
        guard snapshot.lines.indices.contains(range.start.row) else {
            return nil
        }

        let endRow = min(range.end.row, snapshot.lines.index(before: snapshot.lines.endIndex))
        let selectedLines = (range.start.row...endRow).map { rowIndex in
            selectedText(
                from: snapshot.lines[rowIndex],
                row: rowIndex,
                range: range
            )
        }
        return selectedLines.joined(separator: "\n")
    }

    private var normalizedRange: (start: TerminalGridPosition, end: TerminalGridPosition) {
        anchor <= focus ? (anchor, focus) : (focus, anchor)
    }

    private func selectedText(
        from line: TerminalGridLine,
        row: Int,
        range: (start: TerminalGridPosition, end: TerminalGridPosition)
    ) -> String {
        var column = 0
        var text = ""
        let selectedStart = row == range.start.row ? range.start.column : 0
        let selectedEnd = row == range.end.row ? range.end.column : Int.max

        for cell in line.cells {
            if column < selectedEnd && column + cell.width > selectedStart {
                text += cell.text
            }
            column += cell.width
        }

        return text
    }
}
