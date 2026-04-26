import AppKit

struct TerminalTypography {
    static let defaultTextInsets = NSSize(width: 10, height: 8)
    static let contentInsets = NSEdgeInsets(
        top: defaultTextInsets.height,
        left: defaultTextInsets.width,
        bottom: defaultTextInsets.height,
        right: defaultTextInsets.width
    )

    var appearance: TerminalAppearance
    var palette: TerminalAppearancePalette
    var font: NSFont
    var cellSize: CGSize
    var textInsets: NSSize

    init(fontSize: Double) {
        self = Self.make(
            appearance: TerminalAppearance(fontSize: fontSize)
        )
    }

    private init(
        appearance: TerminalAppearance,
        palette: TerminalAppearancePalette,
        font: NSFont,
        cellSize: CGSize,
        textInsets: NSSize
    ) {
        self.appearance = appearance
        self.palette = palette
        self.font = font
        self.cellSize = cellSize
        self.textInsets = textInsets
    }

    static func make(appearance: TerminalAppearance) -> TerminalTypography {
        let font = Self.font(for: appearance.fontSize)
        return TerminalTypography(
            appearance: appearance,
            palette: TerminalAppearancePalette.palette(for: appearance.theme),
            font: font,
            cellSize: Self.cellSize(for: font),
            textInsets: defaultTextInsets
        )
    }

    static func font(for fontSize: Double) -> NSFont {
        let size = CGFloat(TerminalAppearance.clampedFontSize(fontSize))
        return NSFont(name: "SF Mono", size: size)
            ?? NSFont(name: "Menlo", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func cellSize(for fontSize: Double) -> CGSize {
        cellSize(for: font(for: fontSize))
    }

    func font(for style: TerminalTextStyle) -> NSFont {
        var styledFont = font
        if style.isBold {
            styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .boldFontMask)
        }
        if style.isItalic {
            styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .italicFontMask)
        }
        return styledFont
    }

    func foregroundColor(for style: TerminalTextStyle) -> NSColor {
        palette.color(for: style.foreground) ?? palette.foreground
    }

    func backgroundColor(for style: TerminalTextStyle) -> NSColor? {
        palette.color(for: style.background)
    }

    var horizontalInset: CGFloat {
        textInsets.width * 2
    }

    var verticalInset: CGFloat {
        textInsets.height * 2
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = cellSize.height
        style.maximumLineHeight = cellSize.height
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.defaultTabInterval = cellSize.width * 8
        style.tabStops = []
        return style
    }

    func attributes(
        for style: TerminalTextStyle,
        defaultForeground: NSColor,
        palette: TerminalAppearancePalette
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style),
            .foregroundColor: palette.color(for: style.foreground) ?? defaultForeground,
            .paragraphStyle: paragraphStyle,
            .ligature: 0,
            .kern: 0
        ]

        if let backgroundColor = palette.color(for: style.background) {
            attributes[.backgroundColor] = backgroundColor
        }
        if style.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attributes
    }

    private static func cellSize(for font: NSFont) -> CGSize {
        let width = ceil(("W" as NSString).size(withAttributes: [.font: font]).width)
        let height = ceil(font.ascender - font.descender + max(font.leading, 0))
        return CGSize(width: max(1, width), height: max(1, height))
    }
}
