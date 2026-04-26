import AppKit
import SwiftUI

struct TerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    var buffer: String
    var onInput: (String) -> Void

    init(
        buffer: String = "",
        onInput: @escaping (String) -> Void = { _ in }
    ) {
        self.buffer = buffer
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
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.inputHandler = context.coordinator.handleInput

        scrollView.documentView = textView
        updateText(buffer, in: textView)
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

        updateText(buffer, in: textView)
        textView.inputHandler = context.coordinator.handleInput
    }

    private func updateText(_ text: String, in textView: TerminalTextView) {
        guard textView.string != text else {
            return
        }

        let shouldFollowTail = textView.shouldFollowTailOnTextUpdate()
        let visibleOrigin = textView.enclosingScrollView?.contentView.bounds.origin
        textView.string = text
        textView.ensureTextLayout()

        if shouldFollowTail {
            textView.scrollToEndOfDocument(nil)
        } else if let visibleOrigin {
            textView.restoreVisibleOrigin(visibleOrigin)
        }
    }

    final class Coordinator {
        var onInput: (String) -> Void

        init(onInput: @escaping (String) -> Void) {
            self.onInput = onInput
        }

        func handleInput(_ text: String) {
            onInput(text)
        }
    }
}

final class TerminalTextView: NSTextView {
    var inputHandler: ((String) -> Void)?

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
        guard let key = TerminalInputKey(event: event),
              let input = TerminalInputTranslator.input(for: key, modifiers: modifiers) else {
            super.keyDown(with: event)
            return
        }

        inputHandler?(input)
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
