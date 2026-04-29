import AppKit
import CoreText
import SwiftTerm
import XCTest
@testable import Smux

@MainActor
final class TerminalViewModelTests: XCTestCase {
    func testAppendOutputPublishesVisibleOutput() {
        let viewModel = TerminalViewModel()

        viewModel.appendOutput("hello")
        viewModel.appendOutput(Data(" world".utf8))

        XCTAssertEqual(viewModel.visibleOutput, "hello world")
    }

    func testAppendOutputPublishesStyledOutput() {
        let viewModel = TerminalViewModel()

        viewModel.appendOutput("\u{1B}[34;4mblue\u{1B}[0m")

        XCTAssertEqual(viewModel.visibleOutput, "blue")
        XCTAssertEqual(
            viewModel.visibleStyledOutput,
            [
                TerminalStyledTextRun(
                    text: "blue",
                    style: TerminalTextStyle(
                        foreground: .ansi(.blue),
                        background: nil,
                        isBold: false,
                        isItalic: false,
                        isUnderline: true
                    )
                )
            ]
        )
    }

    func testAppendOutputPreservesSplitUTF8ScalarsAcrossChunks() {
        let viewModel = TerminalViewModel()
        let bytes = Array("한".utf8)

        viewModel.appendOutput(Data(bytes.prefix(2)))
        XCTAssertEqual(viewModel.visibleOutput, "")

        viewModel.appendOutput(Data(bytes.suffix(1)))
        XCTAssertEqual(viewModel.visibleOutput, "한")
    }

    func testAppendOutputTruncatesToConfiguredBufferLimit() {
        let viewModel = TerminalViewModel(
            outputBuffer: TerminalOutputBuffer(maximumCharacterCount: 5)
        )

        viewModel.appendOutput("abcdef")
        viewModel.appendOutput("ghi")

        XCTAssertEqual(viewModel.visibleOutput, "efghi")
    }

    func testClearOutputRemovesVisibleOutput() {
        let viewModel = TerminalViewModel()

        viewModel.appendOutput("hello")
        viewModel.clearOutput()

        XCTAssertEqual(viewModel.visibleOutput, "")
    }

    func testTerminalGridViewDelegatesKeyInput() throws {
        let textView = TerminalGridView()
        var inputs: [String] = []
        textView.inputHandler = { inputs.append($0) }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )

        textView.keyDown(with: event)

        XCTAssertEqual(inputs, ["a"])
    }

    func testTerminalGridViewMapsArrowKeysToEscapeSequences() throws {
        let textView = TerminalGridView()
        var inputs: [String] = []
        textView.inputHandler = { inputs.append($0) }
        let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: upArrow,
                charactersIgnoringModifiers: upArrow,
                isARepeat: false,
                keyCode: 126
            )
        )

        textView.keyDown(with: event)

        XCTAssertEqual(inputs, ["\u{1B}[A"])
    }

    func testTerminalGridViewDoesNotForwardCommandShortcutsAsInput() throws {
        let textView = TerminalGridView()
        var inputs: [String] = []
        textView.inputHandler = { inputs.append($0) }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "c",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            )
        )

        textView.keyDown(with: event)

        XCTAssertTrue(inputs.isEmpty)
    }

    func testTerminalGridViewCommitsIMEInsertTextToInputHandler() {
        let textView = TerminalGridView()
        var inputs: [String] = []
        textView.inputHandler = { inputs.append($0) }

        textView.insertText(
            NSAttributedString(string: "한"),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertEqual(inputs, ["한"])
        XCTAssertFalse(textView.hasMarkedText())
    }

    func testTerminalGridViewDoesNotForwardMarkedIMEText() {
        let textView = TerminalGridView()
        var inputs: [String] = []
        textView.inputHandler = { inputs.append($0) }

        textView.setMarkedText(
            "ㅎ",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.markedRange(), NSRange(location: 0, length: 1))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertTrue(inputs.isEmpty)

        textView.insertText(
            "한",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertEqual(inputs, ["한"])
        XCTAssertFalse(textView.hasMarkedText())
    }

    func testTerminalGridViewDefaultsSelectionRangeOutsideIMEComposition() {
        let textView = TerminalGridView()

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testTerminalGridViewExposesTextFinderSelectionGeometry() throws {
        let textView = TerminalGridView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        textView.update(
            snapshot: TerminalGridSnapshot(text: "abc\nfind", styledRuns: []),
            appearance: TerminalAppearance()
        )

        textView.selectedRanges = [NSValue(range: NSRange(location: 4, length: 4))]

        XCTAssertEqual(textView.string, "abc\nfind")
        XCTAssertEqual(textView.firstSelectedRange, NSRange(location: 4, length: 4))
        let rects = try XCTUnwrap(textView.rects(forCharacterRange: NSRange(location: 4, length: 4)))
        XCTAssertEqual(rects.count, 1)
        XCTAssertGreaterThan(rects[0].rectValue.width, 0)
        XCTAssertGreaterThan(rects[0].rectValue.height, 0)
    }

    func testTerminalScrollViewEnablesHorizontalScrollerForLongLines() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        let gridView = TerminalGridView()
        TerminalViewRepresentable.configureScrollView(scrollView)
        scrollView.documentView = gridView

        gridView.update(
            snapshot: TerminalGridSnapshot(text: String(repeating: "x", count: 80), styledRuns: []),
            appearance: TerminalAppearance()
        )

        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(gridView.frame.width, scrollView.contentView.bounds.width)
    }

    func testTerminalCellRendererClipsCellsToDirtyRect() {
        let typography = TerminalTypography.make(appearance: TerminalAppearance())
        let line = TerminalGridLine(
            cells: [
                TerminalGridCell(text: "A"),
                TerminalGridCell(text: "한", width: 2),
                TerminalGridCell(text: "B"),
                TerminalGridCell(text: "C"),
                TerminalGridCell(text: "D")
            ]
        )
        let dirtyRect = NSRect(
            x: typography.textInsets.width + typography.cellSize.width * 2.5,
            y: 0,
            width: typography.cellSize.width * 1.7,
            height: typography.cellSize.height
        )

        let visibleRange = TerminalCellRenderer.visibleCellRange(
            in: line,
            dirtyRect: dirtyRect,
            typography: typography
        )

        XCTAssertEqual(Array(visibleRange), [1, 2, 3])
    }

    func testAttributedRendererAppliesTerminalStyles() throws {
        let style = TerminalTextStyle(
            foreground: .ansi(.red),
            background: .ansi(.brightBlack),
            isBold: true,
            isItalic: false,
            isUnderline: true
        )
        let attributedText = TerminalAttributedTextRenderer.attributedString(
            text: "red",
            styledRuns: [TerminalStyledTextRun(text: "red", style: style)],
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            defaultForeground: .labelColor
        )

        XCTAssertEqual(attributedText.string, "red")
        XCTAssertNotNil(attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertNotNil(attributedText.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            attributedText.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )

        let font = try XCTUnwrap(attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testAttributedRendererUsesThemeAdjustedANSIColors() throws {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let darkAttributedText = TerminalAttributedTextRenderer.attributedString(
            text: "black",
            styledRuns: [
                TerminalStyledTextRun(
                    text: "black",
                    style: TerminalTextStyle(foreground: .ansi(.black))
                )
            ],
            font: font,
            defaultForeground: .labelColor,
            appearance: TerminalAppearance(theme: .dark)
        )
        let lightAttributedText = TerminalAttributedTextRenderer.attributedString(
            text: "white",
            styledRuns: [
                TerminalStyledTextRun(
                    text: "white",
                    style: TerminalTextStyle(foreground: .ansi(.white))
                )
            ],
            font: font,
            defaultForeground: .labelColor,
            appearance: TerminalAppearance(theme: .light)
        )

        let darkBlack = try colorComponent(
            from: darkAttributedText,
            attribute: .foregroundColor
        )
        let lightWhite = try colorComponent(
            from: lightAttributedText,
            attribute: .foregroundColor
        )
        XCTAssertGreaterThan(darkBlack.red, 0.2)
        XCTAssertLessThan(lightWhite.red, 0.8)
    }

    func testTerminalPaletteKeepsAgnosterPromptSegmentsReadableInDarkTheme() throws {
        let palette = TerminalAppearancePalette.palette(for: .dark)
        let defaultForeground = try colorComponents(from: palette.foreground)
        let black = try colorComponents(from: XCTUnwrap(palette.color(for: .ansi(.black))))
        let blue = try colorComponents(from: XCTUnwrap(palette.color(for: .ansi(.blue))))

        XCTAssertGreaterThanOrEqual(contrastRatio(defaultForeground, black), 7)
        XCTAssertGreaterThanOrEqual(contrastRatio(black, blue), 4.5)
    }

    func testTerminalGridSnapshotBuildsStyledCellsAndWideWidths() {
        let redStyle = TerminalTextStyle(foreground: .ansi(.red), isBold: true)
        let snapshot = TerminalGridSnapshot(
            text: "A한\nB",
            styledRuns: [
                TerminalStyledTextRun(text: "A", style: .default),
                TerminalStyledTextRun(text: "한", style: redStyle),
                TerminalStyledTextRun(text: "\nB", style: .default)
            ]
        )

        XCTAssertEqual(snapshot.text, "A한\nB")
        XCTAssertEqual(snapshot.lines.count, 2)
        XCTAssertEqual(snapshot.lines.first?.displayWidth, 3)
        XCTAssertEqual(snapshot.lines.first?.cells.map(\.width), [1, 2])
        XCTAssertEqual(snapshot.lines.first?.cells.last?.style, redStyle)
    }

    func testTerminalGridSelectionCopiesSelectedCellsAcrossRows() {
        let snapshot = TerminalGridSnapshot(text: "A한\nBC", styledRuns: [])
        let selection = TerminalGridSelection(
            anchor: TerminalGridPosition(row: 0, column: 1),
            focus: TerminalGridPosition(row: 1, column: 1)
        )

        XCTAssertTrue(selection.intersects(row: 0, column: 1, width: 2))
        XCTAssertEqual(selection.selectedText(from: snapshot), "한\nB")
    }

    func testTerminalTypographyProvidesStableCellMetrics() {
        let smallTypography = TerminalTypography.make(
            appearance: TerminalAppearance(fontSize: TerminalAppearance.minimumFontSize)
        )
        let largeTypography = TerminalTypography.make(
            appearance: TerminalAppearance(fontSize: TerminalAppearance.maximumFontSize)
        )

        XCTAssertGreaterThan(smallTypography.cellSize.width, 0)
        XCTAssertGreaterThan(smallTypography.cellSize.height, 0)
        XCTAssertGreaterThan(largeTypography.cellSize.width, smallTypography.cellSize.width)
        XCTAssertEqual(smallTypography.textInsets, TerminalTypography.defaultTextInsets)
    }

    func testTerminalPowerlineSymbolRecognizesAgnosterGlyphs() {
        XCTAssertEqual(TerminalPowerlineSymbol(text: "\u{E0A0}"), .branch)
        XCTAssertEqual(TerminalPowerlineSymbol(text: "\u{E0B0}"), .rightSeparator)
        XCTAssertEqual(TerminalPowerlineSymbol(text: "\u{E0B1}"), .rightThinSeparator)
        XCTAssertEqual(TerminalPowerlineSymbol(text: "\u{E0B2}"), .leftSeparator)
        XCTAssertEqual(TerminalPowerlineSymbol(text: "\u{E0B3}"), .leftThinSeparator)
        XCTAssertNil(TerminalPowerlineSymbol(text: "A"))
        XCTAssertNil(TerminalPowerlineSymbol(text: "\u{E0B0}\u{E0A0}"))
    }

    func testSwiftTermGridTerminalViewDrawsPowerlineSymbolPixels() throws {
        let appearance = TerminalAppearance(theme: .dark)
        let cellSize = TerminalTypography.cellSize(for: appearance.fontSize)
        let frame = NSRect(
            x: 0,
            y: 0,
            width: cellSize.width * 8,
            height: cellSize.height
        )
        let terminalView = SwiftTermGridTerminalView(frame: frame)
        let palette = TerminalAppearancePalette.palette(for: appearance.theme)

        terminalView.update(
            outputSnapshot: TerminalOutputByteSnapshot(data: Data("A\u{E0A0}\u{E0B0}B".utf8), startOffset: 0),
            appearance: appearance,
            onInput: { _ in },
            onResize: { _, _ in }
        )
        terminalView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            String(try XCTUnwrap(terminalView.terminalForTesting.getCharacter(col: 1, row: 0))),
            "\u{E0A0}"
        )
        XCTAssertEqual(
            String(try XCTUnwrap(terminalView.terminalForTesting.getCharacter(col: 2, row: 0))),
            "\u{E0B0}"
        )

        let image = try bitmapImage(width: Int(ceil(frame.width)), height: Int(ceil(frame.height)))
        try drawView(terminalView, in: frame, into: image)

        let branchRect = CGRect(
            x: cellSize.width,
            y: 0,
            width: cellSize.width,
            height: cellSize.height
        )
        let branchPixels = countPixels(in: image, rect: branchRect) { color in
            colorDistance(color, palette.background) > 0.25
        }
        let branchBounds = try XCTUnwrap(pixelBounds(in: image, rect: branchRect) { color in
            colorDistance(color, palette.background) > 0.25
        })
        let separatorRect = CGRect(
            x: cellSize.width * 2,
            y: 0,
            width: cellSize.width,
            height: cellSize.height
        )
        let separatorPixels = countPixels(in: image, rect: separatorRect) { color in
            colorDistance(color, palette.background) > 0.25
        }

        XCTAssertGreaterThan(
            branchPixels,
            max(14, Int(branchRect.width * branchRect.height * 0.16))
        )
        XCTAssertLessThan(
            branchPixels,
            Int(branchRect.width * branchRect.height * 0.55)
        )
        XCTAssertGreaterThan(branchBounds.height, branchRect.height * 0.76)
        XCTAssertGreaterThan(branchBounds.width, branchRect.width * 0.52)
        XCTAssertGreaterThan(
            separatorPixels,
            Int(separatorRect.width * separatorRect.height * 0.25)
        )
    }

    func testSwiftTermGridTerminalViewDefersResizeCallback() {
        let appearance = TerminalAppearance(theme: .dark)
        let cellSize = TerminalTypography.cellSize(for: appearance.fontSize)
        let terminalView = SwiftTermGridTerminalView(frame: NSRect(
            x: 0,
            y: 0,
            width: cellSize.width * 80,
            height: cellSize.height * 24
        ))
        let resizeDelivered = expectation(description: "resize delivered after current update")
        var resizeEvents: [TerminalGridSizeEstimator] = []

        terminalView.update(
            outputSnapshot: .empty,
            appearance: appearance,
            onInput: { _ in },
            onResize: { columns, rows in
                resizeEvents.append(TerminalGridSizeEstimator(columns: columns, rows: rows))
                resizeDelivered.fulfill()
            }
        )

        terminalView.setFrameSize(NSSize(
            width: cellSize.width * 96,
            height: cellSize.height * 28
        ))

        XCTAssertTrue(resizeEvents.isEmpty)
        wait(for: [resizeDelivered], timeout: 1)
        XCTAssertEqual(resizeEvents, [TerminalGridSizeEstimator(columns: 96, rows: 28)])
    }

    func testSwiftTermGridTerminalContainerClipsTerminalToBounds() {
        let terminalView = SwiftTermGridTerminalView(
            frame: NSRect(x: 0, y: 0, width: 960, height: 480)
        )
        let container = SwiftTermGridTerminalContainerView(terminalView: terminalView)

        XCTAssertTrue(container.wantsLayer)
        XCTAssertEqual(container.layer?.masksToBounds, true)
        XCTAssertEqual(container.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertEqual(container.intrinsicContentSize.height, NSView.noIntrinsicMetric)

        container.setFrameSize(NSSize(width: 240, height: 120))
        container.layout()

        XCTAssertEqual(terminalView.frame, container.bounds)
    }

    func testTerminalTypographyShapesPowerlineGlyphsThroughFallbackFont() throws {
        let hasPowerlineFallback = [
            "Symbols Nerd Font Mono",
            "Symbols Nerd Font",
            "MesloLGS NF",
            "MesloLGS Nerd Font Mono",
            "JetBrainsMono Nerd Font",
            "Hack Nerd Font"
        ].contains { NSFont(name: $0, size: TerminalAppearance.defaultFontSize) != nil }
        guard hasPowerlineFallback else {
            throw XCTSkip("No Powerline-capable fallback font is available on this runner.")
        }

        let font = TerminalTypography.font(for: TerminalAppearance.defaultFontSize)
        let attributedString = NSAttributedString(
            string: "\u{E0A0}\u{E0B0}\u{E0B1}\u{E0B2}\u{E0B3}",
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let glyphs = runs.flatMap { run -> [CGGlyph] in
            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = Array(repeating: CGGlyph(0), count: glyphCount)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            return glyphs
        }

        XCTAssertEqual(glyphs.count, attributedString.length)
        XCTAssertFalse(glyphs.contains(0))
    }

    func testTerminalGridSizeEstimatorClampsAndUsesInsets() {
        let gridSize = TerminalGridSizeEstimator.estimate(
            size: CGSize(width: 96, height: 50),
            characterWidth: 8,
            rowHeight: 17,
            horizontalInset: 16,
            verticalInset: 16
        )

        XCTAssertEqual(gridSize, TerminalGridSizeEstimator(columns: 10, rows: 2))
        XCTAssertEqual(
            TerminalGridSizeEstimator.estimate(size: .zero),
            TerminalGridSizeEstimator(columns: 1, rows: 1)
        )
    }

    func testTerminalGridSizeEstimatorScalesWithFontSize() {
        let smallFontGridSize = TerminalGridSizeEstimator.estimate(
            size: CGSize(width: 320, height: 180),
            fontSize: TerminalAppearance.minimumFontSize
        )
        let largeFontGridSize = TerminalGridSizeEstimator.estimate(
            size: CGSize(width: 320, height: 180),
            fontSize: TerminalAppearance.maximumFontSize
        )

        XCTAssertGreaterThan(smallFontGridSize.columns, largeFontGridSize.columns)
        XCTAssertGreaterThan(smallFontGridSize.rows, largeFontGridSize.rows)
    }

    func testSendInputAndResizeDelegateToTerminalCoreAndRefreshMetadata() {
        let sessionID = TerminalSession.ID()
        let initialSession = makeSession(
            id: sessionID,
            status: .running,
            title: "cat"
        )
        let updatedSession = makeSession(
            id: sessionID,
            status: .failed,
            title: "cat",
            failureMessage: "Write failed"
        )
        let core = MockTerminalCore()
        core.sessions[sessionID] = updatedSession
        let viewModel = TerminalViewModel(
            session: initialSession,
            terminalCore: core
        )

        viewModel.sendInput("hello")
        viewModel.resize(columns: 100, rows: 30)

        XCTAssertEqual(core.sentInputs.map(\.text), ["hello"])
        XCTAssertEqual(core.sentInputs.map(\.sessionID), [sessionID])
        XCTAssertEqual(core.resizes.map(\.sessionID), [sessionID])
        XCTAssertEqual(core.resizes.map(\.columns), [100])
        XCTAssertEqual(core.resizes.map(\.rows), [30])
        XCTAssertEqual(viewModel.session, updatedSession)
        XCTAssertEqual(viewModel.status, .failed)
        XCTAssertEqual(viewModel.title, "cat")
    }

    private func makeSession(
        id: TerminalSession.ID,
        status: TerminalSessionStatus,
        title: String,
        failureMessage: String? = nil
    ) -> TerminalSession {
        TerminalSession(
            id: id,
            workspaceID: UUID(),
            workingDirectory: URL(fileURLWithPath: "/tmp/SmuxTerminalViewModel"),
            processID: 1,
            shell: nil,
            command: ["cat"],
            status: status,
            title: title,
            createdAt: Date(timeIntervalSince1970: 1),
            lastActivityAt: Date(timeIntervalSince1970: 1),
            lastOutputSummary: nil,
            exitCode: nil,
            failureMessage: failureMessage
        )
    }

    private func colorComponent(
        from attributedText: NSAttributedString,
        attribute: NSAttributedString.Key
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let color = try XCTUnwrap(attributedText.attribute(attribute, at: 0, effectiveRange: nil) as? NSColor)
        return try colorComponents(from: color)
    }

    private func colorComponents(from color: NSColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let resolvedColor = try XCTUnwrap(color.usingColorSpace(.sRGB))
        return (resolvedColor.redComponent, resolvedColor.greenComponent, resolvedColor.blueComponent)
    }

    private func contrastRatio(
        _ lhs: (red: CGFloat, green: CGFloat, blue: CGFloat),
        _ rhs: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> CGFloat {
        let lighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
        let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> CGFloat {
        0.2126 * linearized(color.red) + 0.7152 * linearized(color.green) + 0.0722 * linearized(color.blue)
    }

    private func linearized(_ component: CGFloat) -> CGFloat {
        if component <= 0.03928 {
            return component / 12.92
        }

        return CGFloat(pow(Double((component + 0.055) / 1.055), 2.4))
    }

    private func bitmapImage(width: Int, height: Int) throws -> NSBitmapImageRep {
        try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
    }

    private func drawView(
        _ view: NSView,
        in frame: NSRect,
        into image: NSBitmapImageRep
    ) throws {
        let graphicsContext = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: image))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.clear.setFill()
        frame.fill()
        view.draw(frame)
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func countPixels(
        in image: NSBitmapImageRep,
        rect: CGRect,
        matching predicate: (NSColor) -> Bool
    ) -> Int {
        let minX = max(0, Int(floor(rect.minX)))
        let maxX = min(image.pixelsWide, Int(ceil(rect.maxX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxY = min(image.pixelsHigh, Int(ceil(rect.maxY)))
        var count = 0

        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = image.colorAt(x: x, y: y),
                      color.alphaComponent > 0.1,
                      predicate(color) else {
                    continue
                }
                count += 1
            }
        }

        return count
    }

    private func pixelBounds(
        in image: NSBitmapImageRep,
        rect: CGRect,
        matching predicate: (NSColor) -> Bool
    ) -> CGRect? {
        let minX = max(0, Int(floor(rect.minX)))
        let maxX = min(image.pixelsWide, Int(ceil(rect.maxX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxY = min(image.pixelsHigh, Int(ceil(rect.maxY)))
        var left = maxX
        var right = minX
        var top = maxY
        var bottom = minY

        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = image.colorAt(x: x, y: y),
                      color.alphaComponent > 0.1,
                      predicate(color) else {
                    continue
                }
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }

        guard left <= right, top <= bottom else {
            return nil
        }

        return CGRect(
            x: CGFloat(left),
            y: CGFloat(top),
            width: CGFloat(right - left + 1),
            height: CGFloat(bottom - top + 1)
        )
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let lhs = lhs.usingColorSpace(.deviceRGB),
              let rhs = rhs.usingColorSpace(.deviceRGB) else {
            return 0
        }

        return abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }
}

@MainActor
private final class MockTerminalCore: TerminalCoreControlling {
    var sessions: [TerminalSession.ID: TerminalSession] = [:]
    private(set) var sentInputs: [(text: String, sessionID: TerminalSession.ID)] = []
    private(set) var resizes: [(sessionID: TerminalSession.ID, columns: Int, rows: Int)] = []

    func session(for sessionID: TerminalSession.ID) -> TerminalSession? {
        sessions[sessionID]
    }

    func sendInput(_ text: String, to sessionID: TerminalSession.ID) {
        sentInputs.append((text: text, sessionID: sessionID))
    }

    func sendInput(_ data: Data, to sessionID: TerminalSession.ID) {
        let text = String(data: data, encoding: .utf8) ?? ""
        sentInputs.append((text: text, sessionID: sessionID))
    }

    func resize(sessionID: TerminalSession.ID, columns: Int, rows: Int) {
        resizes.append((sessionID: sessionID, columns: columns, rows: rows))
    }

    func terminate(sessionID: TerminalSession.ID) {}
}
