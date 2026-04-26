import AppKit
import SwiftUI

struct TerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    var buffer: String
    var styledRuns: [TerminalStyledTextRun]
    var appearance: TerminalAppearance
    var onInput: (String) -> Void

    init(
        buffer: String = "",
        styledRuns: [TerminalStyledTextRun] = [],
        appearance: TerminalAppearance = TerminalAppearance(),
        onInput: @escaping (String) -> Void = { _ in }
    ) {
        self.buffer = buffer
        self.styledRuns = styledRuns
        self.appearance = appearance
        self.onInput = onInput
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = TerminalTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.inputHandler = context.coordinator.handleInput

        applyAppearance(to: scrollView, textView: textView)
        scrollView.documentView = textView
        context.coordinator.updateText(
            buffer,
            styledRuns: styledRuns,
            appearance: appearance,
            in: textView
        )
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onInput = onInput
        guard let textView = nsView.documentView as? TerminalTextView else {
            return
        }

        applyAppearance(to: nsView, textView: textView)
        context.coordinator.updateText(
            buffer,
            styledRuns: styledRuns,
            appearance: appearance,
            in: textView
        )
        textView.inputHandler = context.coordinator.handleInput
    }

    private func applyAppearance(to scrollView: NSScrollView, textView: NSTextView) {
        let palette = TerminalAppearancePalette.palette(for: appearance.theme)
        scrollView.backgroundColor = palette.background
        textView.backgroundColor = palette.background
        textView.textColor = palette.foreground
        textView.font = TerminalFontMetrics.font(for: appearance.fontSize)
    }

    final class Coordinator {
        var onInput: (String) -> Void
        private var renderedBuffer = ""
        private var renderedRuns: [TerminalStyledTextRun] = []
        private var renderedAppearance: TerminalAppearance?

        init(onInput: @escaping (String) -> Void) {
            self.onInput = onInput
        }

        func handleInput(_ text: String) {
            onInput(text)
        }

        func updateText(
            _ text: String,
            styledRuns: [TerminalStyledTextRun],
            appearance: TerminalAppearance,
            in textView: TerminalTextView
        ) {
            guard renderedBuffer != text
                    || renderedRuns != styledRuns
                    || renderedAppearance != appearance
                    || textView.string != text else {
                return
            }

            let shouldFollowTail = textView.shouldFollowTailOnTextUpdate()
            let visibleOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            let font = textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let attributedText = TerminalAttributedTextRenderer.attributedString(
                text: text,
                styledRuns: styledRuns,
                font: font,
                defaultForeground: textView.textColor ?? .labelColor,
                appearance: appearance
            )

            textView.textStorage?.setAttributedString(attributedText)
            renderedBuffer = text
            renderedRuns = styledRuns
            renderedAppearance = appearance
            textView.ensureTextLayout()

            if shouldFollowTail {
                textView.scrollToEndOfDocument(nil)
            } else if let visibleOrigin {
                textView.restoreVisibleOrigin(visibleOrigin)
            }
        }
    }
}

private struct TerminalAppearancePalette {
    var background: NSColor
    var foreground: NSColor
    var ansi: [TerminalANSIColor: NSColor]

    static func palette(for theme: TerminalTheme) -> TerminalAppearancePalette {
        switch theme {
        case .system:
            return TerminalAppearancePalette(
                background: .textBackgroundColor,
                foreground: .labelColor,
                ansi: systemANSIColors
            )
        case .light:
            return TerminalAppearancePalette(
                background: .white,
                foreground: .black,
                ansi: lightANSIColors
            )
        case .dark:
            return TerminalAppearancePalette(
                background: NSColor(calibratedWhite: 0.08, alpha: 1),
                foreground: NSColor(calibratedWhite: 0.92, alpha: 1),
                ansi: darkANSIColors
            )
        }
    }

    func color(for color: TerminalTextColor?) -> NSColor? {
        guard case let .ansi(ansiColor) = color else {
            return nil
        }

        return ansi[ansiColor]
    }

    private static let lightANSIColors: [TerminalANSIColor: NSColor] = [
        .black: .black,
        .red: .systemRed,
        .green: .systemGreen,
        .yellow: .systemYellow,
        .blue: .systemBlue,
        .magenta: .systemPurple,
        .cyan: .systemCyan,
        .white: NSColor(calibratedWhite: 0.35, alpha: 1),
        .brightBlack: .systemGray,
        .brightRed: .systemRed,
        .brightGreen: .systemGreen,
        .brightYellow: .systemYellow,
        .brightBlue: .systemBlue,
        .brightMagenta: .systemPink,
        .brightCyan: .systemTeal,
        .brightWhite: NSColor(calibratedWhite: 0.55, alpha: 1)
    ]

    private static let darkANSIColors: [TerminalANSIColor: NSColor] = [
        .black: NSColor(calibratedWhite: 0.45, alpha: 1),
        .red: .systemRed,
        .green: .systemGreen,
        .yellow: .systemYellow,
        .blue: .systemBlue,
        .magenta: .systemPurple,
        .cyan: .systemCyan,
        .white: NSColor(calibratedWhite: 0.9, alpha: 1),
        .brightBlack: NSColor(calibratedWhite: 0.62, alpha: 1),
        .brightRed: .systemRed,
        .brightGreen: .systemGreen,
        .brightYellow: .systemYellow,
        .brightBlue: .systemBlue,
        .brightMagenta: .systemPink,
        .brightCyan: .systemTeal,
        .brightWhite: .white
    ]

    private static let systemANSIColors: [TerminalANSIColor: NSColor] = [
        .black: adaptiveColor(
            light: .black,
            dark: NSColor(calibratedWhite: 0.45, alpha: 1)
        ),
        .red: .systemRed,
        .green: .systemGreen,
        .yellow: .systemYellow,
        .blue: .systemBlue,
        .magenta: .systemPurple,
        .cyan: .systemCyan,
        .white: adaptiveColor(
            light: NSColor(calibratedWhite: 0.35, alpha: 1),
            dark: NSColor(calibratedWhite: 0.9, alpha: 1)
        ),
        .brightBlack: adaptiveColor(
            light: .systemGray,
            dark: NSColor(calibratedWhite: 0.62, alpha: 1)
        ),
        .brightRed: .systemRed,
        .brightGreen: .systemGreen,
        .brightYellow: .systemYellow,
        .brightBlue: .systemBlue,
        .brightMagenta: .systemPink,
        .brightCyan: .systemTeal,
        .brightWhite: adaptiveColor(
            light: NSColor(calibratedWhite: 0.55, alpha: 1),
            dark: .white
        )
    ]

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return dark
            }

            return light
        }
    }
}

private enum TerminalFontMetrics {
    static func font(for fontSize: Double) -> NSFont {
        .monospacedSystemFont(
            ofSize: CGFloat(TerminalAppearance.clampedFontSize(fontSize)),
            weight: .regular
        )
    }

    static func cellSize(for fontSize: Double) -> CGSize {
        let font = font(for: fontSize)
        let width = ceil(("W" as NSString).size(withAttributes: [.font: font]).width)
        let height = ceil(NSLayoutManager().defaultLineHeight(for: font))
        return CGSize(width: max(1, width), height: max(1, height))
    }
}

enum TerminalAttributedTextRenderer {
    static func attributedString(
        text: String,
        styledRuns: [TerminalStyledTextRun],
        font: NSFont,
        defaultForeground: NSColor,
        appearance: TerminalAppearance = TerminalAppearance()
    ) -> NSAttributedString {
        let normalizedRuns = runsMatching(text: text, styledRuns: styledRuns)
        let attributedText = NSMutableAttributedString()
        let palette = TerminalAppearancePalette.palette(for: appearance.theme)

        for run in normalizedRuns {
            attributedText.append(
                NSAttributedString(
                    string: run.text,
                    attributes: attributes(
                        for: run.style,
                        font: font,
                        defaultForeground: defaultForeground,
                        palette: palette
                    )
                )
            )
        }

        return attributedText
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

    private static func attributes(
        for style: TerminalTextStyle,
        font: NSFont,
        defaultForeground: NSColor,
        palette: TerminalAppearancePalette
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: styledFont(baseFont: font, style: style),
            .foregroundColor: palette.color(for: style.foreground) ?? defaultForeground
        ]

        if let backgroundColor = palette.color(for: style.background) {
            attributes[.backgroundColor] = backgroundColor
        }
        if style.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attributes
    }

    private static func styledFont(baseFont: NSFont, style: TerminalTextStyle) -> NSFont {
        var font = baseFont
        if style.isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if style.isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

}

final class TerminalTextView: NSTextView {
    var inputHandler: ((String) -> Void)?
    private var terminalMarkedText = ""
    private var terminalMarkedSelectedRange = NSRange(location: 0, length: 0)

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
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

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        terminalMarkedText = ""
        terminalMarkedSelectedRange = NSRange(location: 0, length: 0)

        guard let input = TerminalInputTextExtractor.text(from: insertString), !input.isEmpty else {
            return
        }

        inputHandler?(input)
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        terminalMarkedText = TerminalInputTextExtractor.text(from: string) ?? ""
        terminalMarkedSelectedRange = selectedRange
    }

    override func unmarkText() {
        terminalMarkedText = ""
        terminalMarkedSelectedRange = NSRange(location: 0, length: 0)
    }

    override func hasMarkedText() -> Bool {
        !terminalMarkedText.isEmpty
    }

    override func markedRange() -> NSRange {
        guard hasMarkedText() else {
            return NSRange(location: NSNotFound, length: 0)
        }

        return NSRange(location: 0, length: (terminalMarkedText as NSString).length)
    }

    override func selectedRange() -> NSRange {
        guard hasMarkedText() else {
            return super.selectedRange()
        }

        return terminalMarkedSelectedRange
    }

    override func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        guard let window else {
            return .zero
        }

        let localRect = bounds.isEmpty ? NSRect(origin: .zero, size: NSSize(width: 1, height: 1)) : bounds
        return window.convertToScreen(convert(localRect, to: nil))
    }

    override func characterIndex(for point: NSPoint) -> Int {
        0
    }

    override func paste(_ sender: Any?) {
        guard let input = NSPasteboard.general.string(forType: .string), !input.isEmpty else {
            return
        }

        inputHandler?(input)
    }

    fileprivate func shouldFollowTailOnTextUpdate() -> Bool {
        guard let scrollView = enclosingScrollView else {
            return true
        }

        ensureTextLayout()
        let visibleBounds = scrollView.contentView.bounds
        return TerminalScrollPolicy.shouldFollowTail(
            visibleMaxY: visibleBounds.maxY,
            visibleHeight: visibleBounds.height,
            documentHeight: bounds.height
        )
    }

    fileprivate func restoreVisibleOrigin(_ origin: NSPoint) {
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

    fileprivate func ensureTextLayout() {
        guard let textContainer else {
            return
        }

        layoutManager?.ensureLayout(for: textContainer)
    }
}

nonisolated enum TerminalInputTextExtractor {
    static func text(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }

        return nil
    }
}

nonisolated struct TerminalInputModifiers: OptionSet, Equatable {
    let rawValue: Int

    static let command = TerminalInputModifiers(rawValue: 1 << 0)
    static let shift = TerminalInputModifiers(rawValue: 1 << 1)
}

extension TerminalInputModifiers {
    init(_ modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: TerminalInputModifiers = []

        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }

        self = modifiers
    }
}

nonisolated enum TerminalInputKey: Equatable {
    case text(String)
    case upArrow
    case downArrow
    case rightArrow
    case leftArrow
    case returnKey
    case deleteBackward
    case deleteForward
    case tab
    case backTab
    case escape
    case home
    case end
    case pageUp
    case pageDown
    case insert
}

extension TerminalInputKey {
    init?(event: NSEvent) {
        if let specialKey = event.specialKey {
            switch specialKey {
            case .upArrow:
                self = .upArrow
                return
            case .downArrow:
                self = .downArrow
                return
            case .rightArrow:
                self = .rightArrow
                return
            case .leftArrow:
                self = .leftArrow
                return
            case .enter, .carriageReturn, .newline:
                self = .returnKey
                return
            case .delete, .backspace:
                self = .deleteBackward
                return
            case .deleteForward:
                self = .deleteForward
                return
            case .tab:
                self = .tab
                return
            case .backTab:
                self = .backTab
                return
            case .home, .begin:
                self = .home
                return
            case .end:
                self = .end
                return
            case .pageUp:
                self = .pageUp
                return
            case .pageDown:
                self = .pageDown
                return
            case .insert:
                self = .insert
                return
            default:
                break
            }
        }

        guard let characters = event.characters, !characters.isEmpty else {
            return nil
        }

        switch characters {
        case "\r", "\n":
            self = .returnKey
        case "\u{7F}", "\u{08}":
            self = .deleteBackward
        case "\t":
            self = .tab
        case "\u{1B}":
            self = .escape
        default:
            self = .text(characters)
        }
    }
}

nonisolated enum TerminalInputTranslator {
    static func input(
        for key: TerminalInputKey,
        modifiers: TerminalInputModifiers = []
    ) -> String? {
        guard !modifiers.contains(.command) else {
            return nil
        }

        switch key {
        case let .text(text):
            return text.isEmpty ? nil : text
        case .upArrow:
            return "\u{1B}[A"
        case .downArrow:
            return "\u{1B}[B"
        case .rightArrow:
            return "\u{1B}[C"
        case .leftArrow:
            return "\u{1B}[D"
        case .returnKey:
            return "\r"
        case .deleteBackward:
            return "\u{7F}"
        case .deleteForward:
            return "\u{1B}[3~"
        case .tab:
            return modifiers.contains(.shift) ? "\u{1B}[Z" : "\t"
        case .backTab:
            return "\u{1B}[Z"
        case .escape:
            return "\u{1B}"
        case .home:
            return "\u{1B}[H"
        case .end:
            return "\u{1B}[F"
        case .pageUp:
            return "\u{1B}[5~"
        case .pageDown:
            return "\u{1B}[6~"
        case .insert:
            return "\u{1B}[2~"
        }
    }
}

nonisolated enum TerminalScrollPolicy {
    static let tailTolerance: CGFloat = 24

    static func shouldFollowTail(
        visibleMaxY: CGFloat,
        visibleHeight: CGFloat,
        documentHeight: CGFloat,
        tolerance: CGFloat = tailTolerance
    ) -> Bool {
        documentHeight <= visibleHeight || visibleMaxY >= documentHeight - tolerance
    }

    static func clampedVisibleOriginY(
        _ originY: CGFloat,
        visibleHeight: CGFloat,
        documentHeight: CGFloat
    ) -> CGFloat {
        min(max(0, originY), max(0, documentHeight - visibleHeight))
    }
}

nonisolated struct TerminalGridSizeEstimator: Equatable {
    var columns: Int
    var rows: Int

    @MainActor
    static func estimate(
        size: CGSize,
        fontSize: Double,
        horizontalInset: CGFloat = 16,
        verticalInset: CGFloat = 16
    ) -> TerminalGridSizeEstimator {
        let cellSize = TerminalFontMetrics.cellSize(for: fontSize)
        return estimate(
            size: size,
            characterWidth: cellSize.width,
            rowHeight: cellSize.height,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset
        )
    }

    static func estimate(
        size: CGSize,
        characterWidth: CGFloat = 8,
        rowHeight: CGFloat = 17,
        horizontalInset: CGFloat = 16,
        verticalInset: CGFloat = 16
    ) -> TerminalGridSizeEstimator {
        let usableWidth = max(0, size.width - horizontalInset)
        let usableHeight = max(0, size.height - verticalInset)
        let safeCharacterWidth = max(1, characterWidth)
        let safeRowHeight = max(1, rowHeight)

        return TerminalGridSizeEstimator(
            columns: max(1, Int(usableWidth / safeCharacterWidth)),
            rows: max(1, Int(usableHeight / safeRowHeight))
        )
    }
}
