import AppKit
#if canImport(MetalKit)
import MetalKit
#endif
import SwiftTerm
import SwiftUI

struct SwiftTermTerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = SwiftTerm.TerminalView

    var outputSnapshot: TerminalOutputByteSnapshot
    var appearance: TerminalAppearance
    var onInput: (Data) -> Void
    var onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let font = TerminalTypography.font(for: appearance.fontSize)
        let cellSize = TerminalTypography.cellSize(for: appearance.fontSize)
        let initialFrame = CGRect(
            x: 0,
            y: 0,
            width: cellSize.width * 80,
            height: cellSize.height * 24
        )
        let terminalView = SwiftTerm.TerminalView(frame: initialFrame, font: font)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.terminalDelegate = context.coordinator

        context.coordinator.update(
            outputSnapshot: outputSnapshot,
            appearance: appearance,
            in: terminalView
        )

        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
            context.coordinator.enableMetalIfAvailable(in: terminalView)
        }

        return terminalView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.onInput = onInput
        context.coordinator.onResize = onResize

        if nsView.terminalDelegate !== context.coordinator {
            nsView.terminalDelegate = context.coordinator
        }

        context.coordinator.update(
            outputSnapshot: outputSnapshot,
            appearance: appearance,
            in: nsView
        )
    }

    final class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        var onInput: (Data) -> Void
        var onResize: (Int, Int) -> Void

        private var renderedEndOffset = 0
        private var hasRenderedOutput = false
        private var renderedAppearance: TerminalAppearance?
        private var didAttemptMetal = false

        init(
            onInput: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void
        ) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func update(
            outputSnapshot: TerminalOutputByteSnapshot,
            appearance: TerminalAppearance,
            in terminalView: SwiftTerm.TerminalView
        ) {
            apply(appearance: appearance, to: terminalView)
            feed(outputSnapshot: outputSnapshot, to: terminalView)
        }

        func enableMetalIfAvailable(in terminalView: SwiftTerm.TerminalView) {
            guard !didAttemptMetal else {
                return
            }

            didAttemptMetal = true

            #if canImport(MetalKit)
            terminalView.metalBufferingMode = .perRowPersistent
            do {
                try terminalView.setUseMetal(true)
            } catch {
                try? terminalView.setUseMetal(false)
            }
            #endif
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else {
                return
            }

            onResize(newCols, newRows)
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            onInput(Data(data))
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            guard let string = String(data: content, encoding: .utf8), !string.isEmpty else {
                return
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

        private func apply(
            appearance: TerminalAppearance,
            to terminalView: SwiftTerm.TerminalView
        ) {
            guard renderedAppearance != appearance else {
                return
            }

            let palette = TerminalAppearancePalette.palette(for: appearance.theme)
            let font = TerminalTypography.font(for: appearance.fontSize)
            if terminalView.font.fontName != font.fontName || terminalView.font.pointSize != font.pointSize {
                terminalView.font = font
            }

            terminalView.nativeForegroundColor = palette.foreground
            terminalView.nativeBackgroundColor = palette.background
            terminalView.layer?.backgroundColor = palette.background.cgColor
            terminalView.caretColor = palette.foreground
            terminalView.useBrightColors = true
            terminalView.allowMouseReporting = true
            terminalView.customBlockGlyphs = true
            terminalView.antiAliasCustomBlockGlyphs = false
            terminalView.installColors(palette.ansiColorsInTerminalOrder.map(swiftTermColor(from:)))
            renderedAppearance = appearance
        }

        private func feed(
            outputSnapshot: TerminalOutputByteSnapshot,
            to terminalView: SwiftTerm.TerminalView
        ) {
            if !hasRenderedOutput {
                renderedEndOffset = outputSnapshot.startOffset
                hasRenderedOutput = true
            } else if renderedEndOffset < outputSnapshot.startOffset
                        || renderedEndOffset > outputSnapshot.endOffset {
                terminalView.getTerminal().resetToInitialState()
                renderedEndOffset = outputSnapshot.startOffset
            }

            guard outputSnapshot.endOffset > renderedEndOffset else {
                return
            }

            let localStartOffset = renderedEndOffset - outputSnapshot.startOffset
            let suffix = Array(outputSnapshot.data.dropFirst(localStartOffset))
            terminalView.feed(byteArray: suffix[...])
            renderedEndOffset = outputSnapshot.endOffset
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

        private func clamp(_ value: CGFloat) -> CGFloat {
            min(max(value, 0), 1)
        }
    }
}
