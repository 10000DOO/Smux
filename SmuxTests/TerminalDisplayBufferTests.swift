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

    func testClearLineRemovesCurrentLineContent() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("old prompt\r\u{1B}[Knew prompt")

        XCTAssertEqual(buffer.text, "new prompt")
    }

    func testClearScreenRemovesPreviousContent() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("before\ncontent\u{1B}[H\u{1B}[2Jafter")

        XCTAssertEqual(buffer.text, "after")
    }

    func testUTF8TextIsPreserved() {
        var buffer = TerminalDisplayBuffer()

        buffer.append("한글 prompt")

        XCTAssertEqual(buffer.text, "한글 prompt")
    }

    func testOutputBufferKeepsRawTextSeparateFromDisplayText() {
        var buffer = TerminalOutputBuffer()

        buffer.append("\u{1B}[31mred\u{1B}[0m")

        XCTAssertEqual(buffer.text, "\u{1B}[31mred\u{1B}[0m")
        XCTAssertEqual(buffer.displayText, "red")
    }
}
