import AppKit
import SwiftTerm
import SwiftUI

struct SwiftTermTerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = SwiftTermGridTerminalContainerView

    var outputSnapshot: TerminalOutputByteSnapshot
    var appearance: TerminalAppearance
    var onInput: (Data) -> Void
    var onResize: (Int, Int) -> Void

    func makeNSView(context: Context) -> SwiftTermGridTerminalContainerView {
        let typography = TerminalTypography.make(appearance: appearance)
        let initialFrame = CGRect(
            x: 0,
            y: 0,
            width: typography.cellSize.width * 80,
            height: typography.cellSize.height * 24
        )
        let view = SwiftTermGridTerminalView(frame: initialFrame)
        let containerView = SwiftTermGridTerminalContainerView(terminalView: view)
        view.update(
            outputSnapshot: outputSnapshot,
            appearance: appearance,
            onInput: onInput,
            onResize: onResize
        )

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return containerView
    }

    func updateNSView(_ nsView: SwiftTermGridTerminalContainerView, context: Context) {
        nsView.update(
            outputSnapshot: outputSnapshot,
            appearance: appearance,
            onInput: onInput,
            onResize: onResize
        )
    }
}

final class SwiftTermGridTerminalContainerView: NSView {
    let terminalView: SwiftTermGridTerminalView

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    init(terminalView: SwiftTermGridTerminalView) {
        self.terminalView = terminalView
        super.init(frame: terminalView.frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        terminalView = SwiftTermGridTerminalView(frame: .zero)
        super.init(coder: coder)
        configureView()
    }

    override func layout() {
        super.layout()
        guard terminalView.frame != bounds else {
            return
        }

        terminalView.frame = bounds
    }

    func update(
        outputSnapshot: TerminalOutputByteSnapshot,
        appearance: TerminalAppearance,
        onInput: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void
    ) {
        terminalView.update(
            outputSnapshot: outputSnapshot,
            appearance: appearance,
            onInput: onInput,
            onResize: onResize
        )
    }

    private func configureView() {
        wantsLayer = true
        layer?.masksToBounds = true
        terminalView.frame = bounds
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
    }
}

final class SwiftTermGridTerminalView: NSView, NSTextInputClient, TerminalDelegate {
    private var terminal: Terminal!
    private var typography = TerminalTypography.make(appearance: TerminalAppearance())
    private var renderedAppearance: TerminalAppearance?
    private var renderedEndOffset = 0
    private var hasRenderedOutput = false
    private var cursorIsVisible = true
    private var terminalMarkedText = ""
    private var terminalMarkedSelectedRange = NSRange(location: 0, length: 0)
    private var pendingResize: TerminalGridSizeEstimator?
    private var isResizeDeliveryScheduled = false
    private lazy var terminalInputContext = NSTextInputContext(client: self)

    var onInput: (Data) -> Void = { _ in }
    var onResize: (Int, Int) -> Void = { _, _ in }

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
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        resizeTerminalToBounds()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeTerminalToBounds()
    }

    func update(
        outputSnapshot: TerminalOutputByteSnapshot,
        appearance: TerminalAppearance,
        onInput: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void
    ) {
        self.onInput = onInput
        self.onResize = onResize
        apply(appearance: appearance)
        feed(outputSnapshot: outputSnapshot)
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
                sendUserInput(input)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let input = NSPasteboard.general.string(forType: .string), !input.isEmpty else {
            return
        }

        sendUserInput(input)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawTerminal(in: dirtyRect)
    }

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        onInput(Data(data))
    }

    func showCursor(source: Terminal) {
        cursorIsVisible = true
        needsDisplay = true
    }

    func hideCursor(source: Terminal) {
        cursorIsVisible = false
        needsDisplay = true
    }

    func scrolled(source: Terminal, yDisp: Int) {
        needsDisplay = true
    }

    func linefeed(source: Terminal) {
        needsDisplay = true
    }

    func bufferActivated(source: Terminal) {
        needsDisplay = true
    }

    func colorChanged(source: Terminal, idx: Int?) {
        needsDisplay = true
    }

    func setForegroundColor(source: Terminal, color: SwiftTerm.Color) {
        source.foregroundColor = color
        needsDisplay = true
    }

    func setBackgroundColor(source: Terminal, color: SwiftTerm.Color) {
        source.backgroundColor = color
        layer?.backgroundColor = nsColor(from: color).cgColor
        needsDisplay = true
    }

    func setCursorColor(source: Terminal, color: SwiftTerm.Color?) {
        source.cursorColor = color
        needsDisplay = true
    }

    func getColors(source: Terminal) -> (foreground: SwiftTerm.Color, background: SwiftTerm.Color) {
        (source.foregroundColor, source.backgroundColor)
    }

    func clipboardCopy(source: Terminal, content: Data) {
        guard let string = String(data: content, encoding: .utf8), !string.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func cellSizeInPixels(source: Terminal) -> (width: Int, height: Int)? {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        return (
            width: Int(ceil(typography.cellSize.width * scale)),
            height: Int(ceil(typography.cellSize.height * scale))
        )
    }

    func insertText(_ insertString: Any, replacementRange: NSRange) {
        terminalMarkedText = ""
        terminalMarkedSelectedRange = NSRange(location: 0, length: 0)

        guard let input = TerminalInputTextExtractor.text(from: insertString), !input.isEmpty else {
            return
        }

        sendUserInput(input)
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

    var terminalForTesting: Terminal {
        terminal
    }

    private func configureView() {
        terminal = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 24))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = typography.palette.background.cgColor
        apply(appearance: typography.appearance)
        resizeTerminalToBounds()
    }

    private func apply(appearance: TerminalAppearance) {
        guard renderedAppearance != appearance else {
            return
        }

        typography = TerminalTypography.make(appearance: appearance)
        layer?.backgroundColor = typography.palette.background.cgColor
        terminal.installPalette(colors: typography.palette.ansiColorsInTerminalOrder.map(swiftTermColor(from:)))
        terminal.foregroundColor = swiftTermColor(from: typography.palette.foreground)
        terminal.backgroundColor = swiftTermColor(from: typography.palette.background)
        renderedAppearance = appearance
        resizeTerminalToBounds()
        needsDisplay = true
    }

    private func feed(outputSnapshot: TerminalOutputByteSnapshot) {
        if !hasRenderedOutput {
            renderedEndOffset = outputSnapshot.startOffset
            hasRenderedOutput = true
        } else if renderedEndOffset < outputSnapshot.startOffset
                    || renderedEndOffset > outputSnapshot.endOffset {
            terminal.resetToInitialState()
            renderedAppearance = nil
            apply(appearance: typography.appearance)
            resizeTerminalToBounds()
            renderedEndOffset = outputSnapshot.startOffset
        }

        guard outputSnapshot.endOffset > renderedEndOffset else {
            return
        }

        let localStartOffset = renderedEndOffset - outputSnapshot.startOffset
        let suffix = Array(outputSnapshot.data.dropFirst(localStartOffset))
        terminal.feed(buffer: suffix[...])
        renderedEndOffset = outputSnapshot.endOffset
        needsDisplay = true
    }

    private func resizeTerminalToBounds() {
        guard terminal != nil, typography.cellSize.width > 0, typography.cellSize.height > 0 else {
            return
        }

        let cols = max(2, Int(floor(bounds.width / typography.cellSize.width)))
        let rows = max(1, Int(floor(bounds.height / typography.cellSize.height)))
        guard cols != terminal.cols || rows != terminal.rows else {
            return
        }

        terminal.resize(cols: cols, rows: rows)
        scheduleResizeDelivery(columns: cols, rows: rows)
        needsDisplay = true
    }

    private func scheduleResizeDelivery(columns: Int, rows: Int) {
        pendingResize = TerminalGridSizeEstimator(columns: columns, rows: rows)
        guard !isResizeDeliveryScheduled else {
            return
        }

        isResizeDeliveryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isResizeDeliveryScheduled = false
            guard let pendingResize = self.pendingResize else {
                return
            }

            self.pendingResize = nil
            self.onResize(pendingResize.columns, pendingResize.rows)
        }
    }

    private func drawTerminal(in dirtyRect: NSRect) {
        typography.palette.background.setFill()
        dirtyRect.fill()

        let firstRow = max(0, Int(floor(dirtyRect.minY / typography.cellSize.height)))
        let lastRow = min(terminal.rows - 1, Int(ceil(dirtyRect.maxY / typography.cellSize.height)))
        guard firstRow <= lastRow else {
            return
        }

        for row in firstRow...lastRow {
            drawRow(row)
        }

        drawCursor(in: dirtyRect)
    }

    private func drawRow(_ row: Int) {
        guard let line = terminal.getLine(row: row) else {
            return
        }

        let columnLimit = min(terminal.cols, line.count)
        var column = 0
        while column < columnLimit {
            let charData = line[column]
            let width = max(1, Int(charData.width))
            let cellRect = rect(row: row, column: column, width: width)

            drawCell(charData, in: cellRect)
            column += width
        }
    }

    private func drawCell(_ charData: CharData, in rect: NSRect) {
        let colors = resolvedColors(for: charData.attribute)
        colors.background.setFill()
        rect.fill()

        guard !charData.attribute.style.contains(.invisible) else {
            return
        }

        let text = String(terminal.getCharacter(for: charData))
        guard text != "\u{0}", !text.isEmpty else {
            return
        }

        let font = font(for: charData.attribute.style)
        if let symbol = TerminalPowerlineSymbol(text: text) {
            symbol.draw(in: rect, foregroundColor: colors.foreground)
            return
        }

        drawText(
            text,
            in: rect,
            attribute: charData.attribute,
            foregroundColor: colors.foreground,
            font: font
        )
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        attribute: Attribute,
        foregroundColor: NSColor,
        font: NSFont
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = typography.cellSize.height
        paragraphStyle.maximumLineHeight = typography.cellSize.height
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle,
            .ligature: 0,
            .kern: 0
        ]

        (text as NSString).draw(in: rect, withAttributes: attributes)

        if attribute.style.contains(.underline) || attribute.underlineStyle != .none {
            let underlineColor = attribute.underlineColor.map { color(for: $0, isForeground: true, isBold: false) }
                ?? foregroundColor
            underlineColor.setStroke()
            let underlineY = rect.maxY - 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: underlineY))
            path.line(to: NSPoint(x: rect.maxX, y: underlineY))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawCursor(in dirtyRect: NSRect) {
        guard cursorIsVisible, window?.firstResponder === self else {
            return
        }

        let location = terminal.getCursorLocation()
        guard location.y >= 0, location.y < terminal.rows else {
            return
        }

        let cursorRect = rect(
            row: location.y,
            column: min(max(0, location.x), max(0, terminal.cols - 1)),
            width: 1
        )
        guard cursorRect.intersects(dirtyRect) else {
            return
        }

        let cursorColor = terminal.cursorColor.map(nsColor(from:)) ?? typography.palette.foreground
        cursorColor.withAlphaComponent(0.75).setFill()

        switch terminal.options.cursorStyle {
        case .blinkUnderline, .steadyUnderline:
            NSRect(x: cursorRect.minX, y: cursorRect.maxY - 2, width: cursorRect.width, height: 2).fill()
        case .blinkBar, .steadyBar:
            NSRect(x: cursorRect.minX, y: cursorRect.minY, width: 2, height: cursorRect.height).fill()
        case .blinkBlock, .steadyBlock:
            cursorRect.fill()
        }
    }

    private func rect(row: Int, column: Int, width: Int) -> NSRect {
        NSRect(
            x: CGFloat(column) * typography.cellSize.width,
            y: CGFloat(row) * typography.cellSize.height,
            width: CGFloat(width) * typography.cellSize.width,
            height: typography.cellSize.height
        )
    }

    private func font(for style: CharacterStyle) -> NSFont {
        var font = typography.font
        if style.contains(.bold) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if style.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private func resolvedColors(for attribute: Attribute) -> (foreground: NSColor, background: NSColor) {
        var foreground = attribute.fg
        var background = attribute.bg
        let isBold = attribute.style.contains(.bold)

        if attribute.style.contains(.inverse) {
            swap(&foreground, &background)
            if foreground == .defaultColor {
                foreground = .defaultInvertedColor
            }
            if background == .defaultColor {
                background = .defaultInvertedColor
            }
        }

        var foregroundColor = color(for: foreground, isForeground: true, isBold: isBold)
        let backgroundColor = color(for: background, isForeground: false, isBold: false)

        if attribute.style.contains(.dim) {
            foregroundColor = blendedColor(foregroundColor, towards: backgroundColor, fraction: 0.5)
        }

        return (foregroundColor, backgroundColor)
    }

    private func color(
        for color: Attribute.Color,
        isForeground: Bool,
        isBold: Bool
    ) -> NSColor {
        switch color {
        case .defaultColor:
            return isForeground ? typography.palette.foreground : typography.palette.background
        case .defaultInvertedColor:
            return inverseColor(isForeground ? typography.palette.foreground : typography.palette.background)
        case let .ansi256(code):
            let index = swiftTermANSIIndex(code, isBold: isBold)
            return colorFor256ColorIndex(index)
                ?? (isForeground ? typography.palette.foreground : typography.palette.background)
        case let .trueColor(red, green, blue):
            return NSColor(
                calibratedRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }
    }

    private func swiftTermANSIIndex(_ code: UInt8, isBold: Bool) -> Int {
        if code < 8 {
            return Int(code) + (isBold ? 8 : 0)
        }
        return Int(code)
    }

    private func colorFor256ColorIndex(_ index: Int) -> NSColor? {
        switch index {
        case 0...15:
            return typography.palette.ansiColorsInTerminalOrder[index]
        case 16...231:
            let colorIndex = index - 16
            let red = colorIndex / 36
            let green = (colorIndex % 36) / 6
            let blue = colorIndex % 6
            return NSColor(
                calibratedRed: colorCubeComponent(red),
                green: colorCubeComponent(green),
                blue: colorCubeComponent(blue),
                alpha: 1
            )
        case 232...255:
            let component = CGFloat(8 + (index - 232) * 10) / 255
            return NSColor(calibratedWhite: component, alpha: 1)
        default:
            return nil
        }
    }

    private func colorCubeComponent(_ component: Int) -> CGFloat {
        component == 0 ? 0 : CGFloat(55 + component * 40) / 255
    }

    private func inverseColor(_ color: NSColor) -> NSColor {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return NSColor(
            deviceRed: 1 - red,
            green: 1 - green,
            blue: 1 - blue,
            alpha: alpha
        )
    }

    private func blendedColor(
        _ color: NSColor,
        towards background: NSColor,
        fraction: CGFloat
    ) -> NSColor {
        let colorRGB = color.usingColorSpace(.deviceRGB) ?? color
        let backgroundRGB = background.usingColorSpace(.deviceRGB) ?? background
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        var backgroundRed: CGFloat = 0
        var backgroundGreen: CGFloat = 0
        var backgroundBlue: CGFloat = 0
        var backgroundAlpha: CGFloat = 1

        colorRGB.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        backgroundRGB.getRed(
            &backgroundRed,
            green: &backgroundGreen,
            blue: &backgroundBlue,
            alpha: &backgroundAlpha
        )

        let clampedFraction = min(max(fraction, 0), 1)
        return NSColor(
            deviceRed: red + ((backgroundRed - red) * clampedFraction),
            green: green + ((backgroundGreen - green) * clampedFraction),
            blue: blue + ((backgroundBlue - blue) * clampedFraction),
            alpha: alpha + ((backgroundAlpha - alpha) * clampedFraction)
        )
    }

    private func sendUserInput(_ input: String) {
        onInput(Data(input.utf8))
    }

    private func swiftTermColor(from color: NSColor) -> SwiftTerm.Color {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return SwiftTerm.Color(
            red: UInt16(clamp(red) * 65_535),
            green: UInt16(clamp(green) * 65_535),
            blue: UInt16(clamp(blue) * 65_535)
        )
    }

    private func nsColor(from color: SwiftTerm.Color) -> NSColor {
        NSColor(
            deviceRed: CGFloat(color.red) / 65_535,
            green: CGFloat(color.green) / 65_535,
            blue: CGFloat(color.blue) / 65_535,
            alpha: 1
        )
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
