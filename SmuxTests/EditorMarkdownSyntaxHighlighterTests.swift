import AppKit
import XCTest
@testable import Smux

@MainActor
final class EditorMarkdownSyntaxHighlighterTests: XCTestCase {
    func testStylesCommonMarkdownTokens() throws {
        let text = """
        # Heading

        Body with `inline code`, **strong text**, and [link](https://example.com).
        """
        let attributedText = MarkdownEditorSyntaxHighlighter.attributedString(
            for: text,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        let nsText = text as NSString

        let headingFont = try XCTUnwrap(
            attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))

        let inlineCodeRange = nsText.range(of: "`inline code`")
        XCTAssertNotNil(
            attributedText.attribute(.backgroundColor, at: inlineCodeRange.location, effectiveRange: nil)
        )

        let strongRange = nsText.range(of: "**strong text**")
        let strongFont = try XCTUnwrap(
            attributedText.attribute(.font, at: strongRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: strongFont).contains(.boldFontMask))

        let linkRange = nsText.range(of: "[link](https://example.com)")
        XCTAssertEqual(
            attributedText.attribute(.underlineStyle, at: linkRange.location, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
    }

    func testFencedCodeBlockSuppressesNestedMarkdownHighlighting() throws {
        let text = """
        ```markdown
        # not a heading
        [not link](https://example.com)
        ```
        """
        let attributedText = MarkdownEditorSyntaxHighlighter.attributedString(
            for: text,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        let nsText = text as NSString
        let headingRange = nsText.range(of: "# not a heading")
        let linkRange = nsText.range(of: "[not link](https://example.com)")

        XCTAssertNotNil(
            attributedText.attribute(.backgroundColor, at: headingRange.location, effectiveRange: nil)
        )

        let headingFont = try XCTUnwrap(
            attributedText.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertFalse(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))
        XCTAssertNil(attributedText.attribute(.underlineStyle, at: linkRange.location, effectiveRange: nil))
    }

    func testApplyHighlightingPreservesSelection() {
        let textView = NSTextView()
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = "# Heading\n\nBody"
        textView.setSelectedRange(NSRange(location: 2, length: 4))

        MarkdownEditorSyntaxHighlighter.applyHighlighting(to: textView)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 4))
    }

    func testApplyHighlightingDoesNotEmitTextChangeNotification() {
        let textView = NSTextView()
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = "# Heading"
        var changeNotificationCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: nil
        ) { _ in
            changeNotificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        MarkdownEditorSyntaxHighlighter.applyHighlighting(to: textView)

        XCTAssertEqual(changeNotificationCount, 0)
    }
}
