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

    func testTerminalTextViewDelegatesKeyInput() throws {
        let textView = TerminalTextView()
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

    func testTerminalTextViewMapsArrowKeysToEscapeSequences() throws {
        let textView = TerminalTextView()
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

    func testTerminalTextViewDoesNotForwardCommandShortcutsAsInput() throws {
        let textView = TerminalTextView()
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
