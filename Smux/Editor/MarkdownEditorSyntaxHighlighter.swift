import AppKit

@MainActor
enum MarkdownEditorSyntaxHighlighter {
    static func applyHighlighting(to textView: NSTextView) {
        guard !textView.hasMarkedText() else {
            return
        }

        let selectedRanges = textView.selectedRanges
        let attributedText = attributedString(
            for: textView.string,
            font: textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            defaultForeground: textView.textColor ?? .textColor
        )

        textView.textStorage?.setAttributedString(attributedText)
        textView.selectedRanges = selectedRanges
    }

    static func attributedString(
        for text: String,
        font: NSFont,
        defaultForeground: NSColor = .textColor
    ) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes(font: font, foreground: defaultForeground)
        )
        let fencedCodeRanges = fencedCodeBlockRanges(in: text)

        applyLineRule(
            pattern: #"^ {0,3}#{1,6}[ \t]+[^\n]+"#,
            attributes: [
                .font: boldFont(from: font),
                .foregroundColor: NSColor.systemBlue
            ],
            to: attributedText,
            excluding: fencedCodeRanges
        )
        applyLineRule(
            pattern: #"^ {0,3}>[^\n]*"#,
            attributes: [.foregroundColor: NSColor.tertiaryLabelColor],
            to: attributedText,
            excluding: fencedCodeRanges
        )
        applyLineRule(
            pattern: #"^ {0,3}(?:[-*+]|\d+\.)[ \t]+"#,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor],
            to: attributedText,
            excluding: fencedCodeRanges
        )
        applyInlineRule(
            pattern: #"`[^`\n]+`"#,
            attributes: inlineCodeAttributes(),
            to: attributedText,
            excluding: fencedCodeRanges
        )
        applyInlineRule(
            pattern: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#,
            attributes: [.font: boldFont(from: font)],
            to: attributedText,
            excluding: fencedCodeRanges
        )
        applyInlineRule(
            pattern: #"!?\[[^\]\n]+\]\([^\)\n]+\)"#,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ],
            to: attributedText,
            excluding: fencedCodeRanges
        )

        for range in fencedCodeRanges {
            attributedText.addAttributes(fencedCodeAttributes(), range: range)
        }

        return attributedText
    }

    private static func baseAttributes(
        font: NSFont,
        foreground: NSColor
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: foreground
        ]
    }

    private static func inlineCodeAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.systemPurple,
            .backgroundColor: NSColor.controlBackgroundColor
        ]
    }

    private static func fencedCodeAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.secondaryLabelColor,
            .backgroundColor: NSColor.controlBackgroundColor
        ]
    }

    private static func boldFont(from font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func applyLineRule(
        pattern: String,
        attributes: [NSAttributedString.Key: Any],
        to attributedText: NSMutableAttributedString,
        excluding excludedRanges: [NSRange]
    ) {
        applyRule(
            pattern: pattern,
            options: [.anchorsMatchLines],
            attributes: attributes,
            to: attributedText,
            excluding: excludedRanges
        )
    }

    private static func applyInlineRule(
        pattern: String,
        attributes: [NSAttributedString.Key: Any],
        to attributedText: NSMutableAttributedString,
        excluding excludedRanges: [NSRange]
    ) {
        applyRule(
            pattern: pattern,
            options: [],
            attributes: attributes,
            to: attributedText,
            excluding: excludedRanges
        )
    }

    private static func applyRule(
        pattern: String,
        options: NSRegularExpression.Options,
        attributes: [NSAttributedString.Key: Any],
        to attributedText: NSMutableAttributedString,
        excluding excludedRanges: [NSRange]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return
        }
        let fullRange = NSRange(location: 0, length: attributedText.length)

        regex.enumerateMatches(in: attributedText.string, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range,
                  range.location != NSNotFound,
                  !range.intersects(any: excludedRanges) else {
                return
            }

            attributedText.addAttributes(attributes, range: range)
        }
    }

    private static func fencedCodeBlockRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var ranges: [NSRange] = []
        var currentStart: Int?
        var delimiter: String?

        nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosingRange, _ in
            let line = nsText.substring(with: lineRange)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if let start = currentStart, let activeDelimiter = delimiter {
                guard trimmedLine.hasPrefix(activeDelimiter) else {
                    return
                }

                ranges.append(NSRange(location: start, length: NSMaxRange(enclosingRange) - start))
                currentStart = nil
                delimiter = nil
                return
            }

            if trimmedLine.hasPrefix("```") {
                currentStart = enclosingRange.location
                delimiter = "```"
            } else if trimmedLine.hasPrefix("~~~") {
                currentStart = enclosingRange.location
                delimiter = "~~~"
            }
        }

        if let currentStart {
            ranges.append(NSRange(location: currentStart, length: nsText.length - currentStart))
        }

        return ranges
    }
}

private extension NSRange {
    func intersects(any ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(self, $0).length > 0 }
    }
}
