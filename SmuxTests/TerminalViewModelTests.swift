import AppKit
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

    func resize(sessionID: TerminalSession.ID, columns: Int, rows: Int) {
        resizes.append((sessionID: sessionID, columns: columns, rows: rows))
    }

    func terminate(sessionID: TerminalSession.ID) {}
}
