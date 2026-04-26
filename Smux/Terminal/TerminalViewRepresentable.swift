import AppKit
import SwiftUI

struct TerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    var snapshot: TerminalGridSnapshot
    var appearance: TerminalAppearance
    var onInput: (String) -> Void

    init(
        snapshot: TerminalGridSnapshot,
        appearance: TerminalAppearance = TerminalAppearance(),
        onInput: @escaping (String) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.appearance = appearance
        self.onInput = onInput
    }

    init(
        buffer: String = "",
        styledRuns: [TerminalStyledTextRun] = [],
        appearance: TerminalAppearance = TerminalAppearance(),
        onInput: @escaping (String) -> Void = { _ in }
    ) {
        self.snapshot = TerminalGridSnapshot(text: buffer, styledRuns: styledRuns)
        self.appearance = appearance
        self.onInput = onInput
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        Self.configureScrollView(scrollView)

        let gridView = TerminalGridView()
        gridView.autoresizingMask = [.width]
        gridView.inputHandler = context.coordinator.handleInput

        applyAppearance(to: scrollView)
        scrollView.documentView = gridView
        gridView.update(snapshot: snapshot, appearance: appearance)
        context.coordinator.updateSnapshot(
            snapshot,
            appearance: appearance,
            in: gridView
        )
        DispatchQueue.main.async {
            gridView.window?.makeFirstResponder(gridView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onInput = onInput
        guard let gridView = nsView.documentView as? TerminalGridView else {
            return
        }

        applyAppearance(to: nsView)
        context.coordinator.updateSnapshot(
            snapshot,
            appearance: appearance,
            in: gridView
        )
        gridView.inputHandler = context.coordinator.handleInput
    }

    private func applyAppearance(to scrollView: NSScrollView) {
        let palette = TerminalAppearancePalette.palette(for: appearance.theme)
        scrollView.backgroundColor = palette.background
    }

    static func configureScrollView(_ scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
    }

    final class Coordinator {
        var onInput: (String) -> Void
        private var renderedSnapshot = TerminalGridSnapshot.empty
        private var renderedAppearance: TerminalAppearance?

        init(onInput: @escaping (String) -> Void) {
            self.onInput = onInput
        }

        func handleInput(_ text: String) {
            onInput(text)
        }

        func updateSnapshot(
            _ snapshot: TerminalGridSnapshot,
            appearance: TerminalAppearance,
            in gridView: TerminalGridView
        ) {
            let previousFrameSize = gridView.frame.size
            gridView.resizeToFitVisibleWidth()
            let didResize = previousFrameSize != gridView.frame.size
            guard renderedSnapshot != snapshot
                    || renderedAppearance != appearance
                    || didResize else {
                return
            }

            let shouldFollowTail = gridView.shouldFollowTailOnTextUpdate()
            let visibleOrigin = gridView.enclosingScrollView?.contentView.bounds.origin
            gridView.update(snapshot: snapshot, appearance: appearance)
            renderedSnapshot = snapshot
            renderedAppearance = appearance

            if shouldFollowTail {
                gridView.scrollToEnd()
            } else if let visibleOrigin {
                gridView.restoreVisibleOrigin(visibleOrigin)
            }
        }
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
        horizontalInset: CGFloat = TerminalTypography.contentInsets.left + TerminalTypography.contentInsets.right,
        verticalInset: CGFloat = TerminalTypography.contentInsets.top + TerminalTypography.contentInsets.bottom
    ) -> TerminalGridSizeEstimator {
        let cellSize = TerminalTypography(fontSize: fontSize).cellSize
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
