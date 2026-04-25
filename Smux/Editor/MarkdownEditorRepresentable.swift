import AppKit
import SwiftUI

struct MarkdownEditorRepresentable: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    var text: String
    var selectedRange: NSRange?
    var onTextChange: (String) -> Void
    var onSelectionChange: (NSRange?) -> Void

    init(
        text: String,
        selectedRange: NSRange? = nil,
        onTextChange: @escaping (String) -> Void = { _ in },
        onSelectionChange: @escaping (NSRange?) -> Void = { _ in }
    ) {
        self.text = text
        self.selectedRange = selectedRange
        self.onTextChange = onTextChange
        self.onSelectionChange = onSelectionChange
    }

    init(text: Binding<String>, selectedRange: Binding<NSRange?>? = nil) {
        self.init(
            text: text.wrappedValue,
            selectedRange: selectedRange?.wrappedValue,
            onTextChange: { text.wrappedValue = $0 },
            onSelectionChange: { selectedRange?.wrappedValue = $0 }
        )
    }

    @MainActor
    init(viewModel: DocumentEditorViewModel) {
        self.init(
            text: viewModel.text,
            selectedRange: viewModel.selectedRange,
            onTextChange: { [weak viewModel] updatedText in
                viewModel?.updateText(updatedText)
            },
            onSelectionChange: { [weak viewModel] updatedRange in
                viewModel?.updateSelectedRange(updatedRange)
            }
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.usesFontPanel = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.sync(textView: textView, text: text, selectedRange: selectedRange)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.sync(textView: textView, text: text, selectedRange: selectedRange)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTextChange: onTextChange,
            onSelectionChange: onSelectionChange
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: (String) -> Void
        var onSelectionChange: (NSRange?) -> Void

        private var isApplyingExternalText = false

        init(
            onTextChange: @escaping (String) -> Void,
            onSelectionChange: @escaping (NSRange?) -> Void
        ) {
            self.onTextChange = onTextChange
            self.onSelectionChange = onSelectionChange
        }

        func sync(textView: NSTextView, text: String, selectedRange: NSRange?) {
            if MarkdownEditorTextSynchronization.shouldApplyText(
                currentText: textView.string,
                incomingText: text
            ) {
                let fallbackRange = textView.selectedRange()
                let rangeToRestore = MarkdownEditorTextSynchronization.selectionRange(
                    preferredRange: selectedRange,
                    fallbackRange: fallbackRange,
                    text: text
                )

                isApplyingExternalText = true
                defer {
                    isApplyingExternalText = false
                }
                textView.string = text
                textView.setSelectedRange(rangeToRestore)
                return
            }

            guard let selectedRange else {
                return
            }

            let nextRange = MarkdownEditorTextSynchronization.selectionRange(
                preferredRange: selectedRange,
                fallbackRange: textView.selectedRange(),
                text: textView.string
            )

            guard nextRange != textView.selectedRange() else {
                return
            }

            textView.setSelectedRange(nextRange)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView
            else {
                return
            }

            onTextChange(textView.string)
            onSelectionChange(textView.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView
            else {
                return
            }

            onSelectionChange(textView.selectedRange())
        }
    }
}

nonisolated enum MarkdownEditorTextSynchronization {
    static func shouldApplyText(currentText: String, incomingText: String) -> Bool {
        currentText != incomingText
    }

    static func selectionRange(
        preferredRange: NSRange?,
        fallbackRange: NSRange,
        text: String
    ) -> NSRange {
        clampedRange(preferredRange, text: text)
            ?? clampedRange(fallbackRange, text: text)
            ?? NSRange(location: textLength(for: text), length: 0)
    }

    static func clampedRange(_ range: NSRange?, text: String) -> NSRange? {
        guard let range, range.location != NSNotFound else {
            return nil
        }

        let length = textLength(for: text)
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)

        return NSRange(
            location: location,
            length: min(max(0, range.length), maxLength)
        )
    }

    private static func textLength(for text: String) -> Int {
        (text as NSString).length
    }
}
