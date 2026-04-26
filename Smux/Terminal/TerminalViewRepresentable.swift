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

        textView.string = text
        textView.scrollToEndOfDocument(nil)
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
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            super.keyDown(with: event)
            return
        }

        switch event.specialKey {
        case .upArrow:
            inputHandler?("\u{1B}[A")
            return
        case .downArrow:
            inputHandler?("\u{1B}[B")
            return
        case .rightArrow:
            inputHandler?("\u{1B}[C")
            return
        case .leftArrow:
            inputHandler?("\u{1B}[D")
            return
        default:
            break
        }

        guard let input = event.characters, !input.isEmpty else {
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
