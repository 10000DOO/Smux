import XCTest
@testable import Smux

final class EditorMarkdownEditorTextSynchronizationTests: XCTestCase {
    func testShouldApplyTextOnlyWhenTextDiffers() {
        XCTAssertFalse(
            MarkdownEditorTextSynchronization.shouldApplyText(
                currentText: "body",
                incomingText: "body"
            )
        )
        XCTAssertTrue(
            MarkdownEditorTextSynchronization.shouldApplyText(
                currentText: "body",
                incomingText: "updated"
            )
        )
    }

    func testSelectionRangePrefersValidPreferredRange() {
        let selectedRange = MarkdownEditorTextSynchronization.selectionRange(
            preferredRange: NSRange(location: 2, length: 3),
            fallbackRange: NSRange(location: 0, length: 1),
            text: "abcdef"
        )

        XCTAssertEqual(selectedRange.location, 2)
        XCTAssertEqual(selectedRange.length, 3)
    }

    func testSelectionRangeClampsPreferredRangeToTextLength() {
        let selectedRange = MarkdownEditorTextSynchronization.selectionRange(
            preferredRange: NSRange(location: 4, length: 10),
            fallbackRange: NSRange(location: 1, length: 1),
            text: "abcdef"
        )

        XCTAssertEqual(selectedRange.location, 4)
        XCTAssertEqual(selectedRange.length, 2)
    }

    func testSelectionRangeFallsBackWhenPreferredRangeIsInvalid() {
        let selectedRange = MarkdownEditorTextSynchronization.selectionRange(
            preferredRange: NSRange(location: NSNotFound, length: 0),
            fallbackRange: NSRange(location: 2, length: 10),
            text: "abcd"
        )

        XCTAssertEqual(selectedRange.location, 2)
        XCTAssertEqual(selectedRange.length, 2)
    }

    func testSelectionRangeMovesToEndWhenAllRangesAreInvalid() {
        let selectedRange = MarkdownEditorTextSynchronization.selectionRange(
            preferredRange: NSRange(location: NSNotFound, length: 0),
            fallbackRange: NSRange(location: NSNotFound, length: 0),
            text: "abcd"
        )

        XCTAssertEqual(selectedRange.location, 4)
        XCTAssertEqual(selectedRange.length, 0)
    }
}
