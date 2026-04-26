import XCTest
@testable import Smux

final class TerminalDisplayBufferTests: XCTestCase {
    func testCarriageReturnReplacesCurrentLine() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("Downloading 10%")
        buffer.append("\rDownloading 20%")

        XCTAssertEqual(buffer.text, "Downloading 20%")
    }

    func testCarriageReturnLineFeedPreservesCompletedLine() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("first\r\nsecond")

        XCTAssertEqual(buffer.text, "first\nsecond")
    }

    func testBackspaceRemovesPreviousCharacter() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("abc\u{08}d")

        XCTAssertEqual(buffer.text, "abd")
    }

    func testANSIStyleSequencesAreStripped() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("\u{1B}[31;1mred\u{1B}[0m plain")

        XCTAssertEqual(buffer.text, "red plain")
    }

    func testANSIStyleSequencesCreateStyledRuns() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("\u{1B}[31;1;4mred\u{1B}[0m plain")

        XCTAssertEqual(
            buffer.styledRuns,
            [
                TerminalStyledTextRun(
                    text: "red",
                    style: TerminalTextStyle(
                        foreground: .ansi(.red),
                        background: nil,
                        isBold: true,
                        isItalic: false,
                        isUnderline: true
                    )
                ),
                TerminalStyledTextRun(text: " plain", style: .default)
            ]
        )
    }

    func testANSIStyledCursorOverwriteUpdatesStyledRuns() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("a\u{1B}[31mb\u{1B}[0m\u{1B}[1D\u{1B}[32mX")

        XCTAssertEqual(buffer.text, "aX")
        XCTAssertEqual(
            buffer.styledRuns,
            [
                TerminalStyledTextRun(text: "a", style: .default),
                TerminalStyledTextRun(
                    text: "X",
                    style: TerminalTextStyle(
                        foreground: .ansi(.green),
                        background: nil,
                        isBold: false,
                        isItalic: false,
                        isUnderline: false
                    )
                )
            ]
        )
    }

    func testClearLineRemovesCurrentLineContent() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("old prompt\r\u{1B}[Knew prompt")

        XCTAssertEqual(buffer.text, "new prompt")
    }

    func testClearLineToCursorKeepsCursorColumn() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("abcdef\u{1B}[3G\u{1B}[1KZ")

        XCTAssertEqual(buffer.text, "  Zdef")
    }

    func testClearScreenRemovesPreviousContent() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("before\ncontent\u{1B}[H\u{1B}[2Jafter")

        XCTAssertEqual(buffer.text, "after")
    }

    func testClearScreenFromCursorPreservesPreviousContent() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("one\ntwo\nthree\u{1B}[2;2H\u{1B}[J")

        XCTAssertEqual(buffer.text, "one\nt")
    }

    func testClearScreenToCursorPreservesFollowingContent() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("one\ntwo\nthree\u{1B}[2;2H\u{1B}[1J")

        XCTAssertEqual(buffer.text, "\n  o\nthree")
    }

    func testCursorMovementOverwritesExistingCells() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("hello\u{1B}[2DXY")

        XCTAssertEqual(buffer.text, "helXY")
    }

    func testWideCharacterCursorMovementUsesDisplayCells() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("한b\u{1B}[3G!")

        XCTAssertEqual(buffer.text, "한!")
    }

    func testWritingInsideWideCharacterBlanksCoveredCell() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("한b\u{1B}[2D!")

        XCTAssertEqual(buffer.text, " !b")
    }

    func testWideCharacterBackspaceRemovesWholeCell() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("한\u{08}A")

        XCTAssertEqual(buffer.text, "A")
    }

    func testClearLineToCursorPreservesWideCellWidth() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("한ab\u{1B}[3G\u{1B}[1KZ")

        XCTAssertEqual(buffer.text, "  Zb")
    }

    func testAlternateScreenRestoresPrimaryDisplayAndCursor() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("prompt")
        buffer.append("\u{1B}[?1049halter")

        XCTAssertEqual(buffer.text, "alter")

        buffer.append("\u{1B}[?1049l done")

        XCTAssertEqual(buffer.text, "prompt done")
    }

    func testTerminalFixtureHandlesAlternateScreenAndCursorUpdates() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("ready")
        buffer.append("\u{1B}[?1049hloading\u{1B}[2DOK\u{1B}[?1049l")

        XCTAssertEqual(buffer.text, "ready")
    }

    func testUTF8TextIsPreserved() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("한글 prompt")

        XCTAssertEqual(buffer.text, "한글 prompt")
    }

    func testScrollbackTruncationDropsWholeLeadingLines() {
        var buffer = TerminalDisplayBuffer(maximumCharacterCount: 5)

        buffer.append("one\ntwo\nthree")

        XCTAssertEqual(buffer.text, "three")
    }

    func testScrollbackTruncationDropsLeadingCellsOnSingleLine() {
        var buffer = TerminalDisplayBuffer(maximumCharacterCount: 3)

        buffer.append("abcd")

        XCTAssertEqual(buffer.text, "bcd")
    }

    func testScrollbackTruncationPreservesStyledRuns() {
        var buffer = TerminalDisplayBuffer(maximumCharacterCount: 8)

        buffer.append("plain\n\u{1B}[32mgreen\u{1B}[0m")

        XCTAssertEqual(buffer.text, "green")
        XCTAssertEqual(
            buffer.styledRuns,
            [
                TerminalStyledTextRun(
                    text: "green",
                    style: TerminalTextStyle(
                        foreground: .ansi(.green),
                        background: nil,
                        isBold: false,
                        isItalic: false,
                        isUnderline: false
                    )
                )
            ]
        )
    }

    func testOutputBufferKeepsRawTextSeparateFromDisplayText() {
        var buffer = TerminalOutputBuffer()

        buffer.append("\u{1B}[31mred\u{1B}[0m")

        XCTAssertEqual(buffer.text, "\u{1B}[31mred\u{1B}[0m")
        XCTAssertEqual(buffer.displayText, "red")
        XCTAssertEqual(
            buffer.displayRuns,
            [
                TerminalStyledTextRun(
                    text: "red",
                    style: TerminalTextStyle(
                        foreground: .ansi(.red),
                        background: nil,
                        isBold: false,
                        isItalic: false,
                        isUnderline: false
                    )
                )
            ]
        )
    }
}
