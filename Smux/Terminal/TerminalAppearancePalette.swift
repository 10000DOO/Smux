import AppKit

struct TerminalAppearancePalette {
    var background: NSColor
    var foreground: NSColor
    var ansi: [TerminalANSIColor: NSColor]

    static func palette(for theme: TerminalTheme) -> TerminalAppearancePalette {
        switch theme {
        case .system:
            return TerminalAppearancePalette(
                background: .textBackgroundColor,
                foreground: .labelColor,
                ansi: systemANSIColors
            )
        case .light:
            return TerminalAppearancePalette(
                background: .white,
                foreground: .black,
                ansi: lightANSIColors
            )
        case .dark:
            return TerminalAppearancePalette(
                background: NSColor(calibratedWhite: 0.08, alpha: 1),
                foreground: NSColor(calibratedWhite: 0.92, alpha: 1),
                ansi: darkANSIColors
            )
        }
    }

    func color(for color: TerminalTextColor?) -> NSColor? {
        guard case let .ansi(ansiColor) = color else {
            return nil
        }

        return ansi[ansiColor]
    }

    private static let darkReadableBlack = NSColor(calibratedWhite: 0.22, alpha: 1)
    private static let darkReadableBlue = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1, alpha: 1)

    private static let lightANSIColors: [TerminalANSIColor: NSColor] = [
        .black: .black,
        .red: .systemRed,
        .green: .systemGreen,
        .yellow: .systemYellow,
        .blue: .systemBlue,
        .magenta: .systemPurple,
        .cyan: .systemCyan,
        .white: NSColor(calibratedWhite: 0.35, alpha: 1),
        .brightBlack: .systemGray,
        .brightRed: .systemRed,
        .brightGreen: .systemGreen,
        .brightYellow: .systemYellow,
        .brightBlue: .systemBlue,
        .brightMagenta: .systemPink,
        .brightCyan: .systemTeal,
        .brightWhite: NSColor(calibratedWhite: 0.55, alpha: 1)
    ]

    private static let darkANSIColors: [TerminalANSIColor: NSColor] = [
        .black: darkReadableBlack,
        .red: .systemRed,
        .green: .systemGreen,
        .yellow: .systemYellow,
        .blue: darkReadableBlue,
        .magenta: .systemPurple,
        .cyan: .systemCyan,
        .white: NSColor(calibratedWhite: 0.9, alpha: 1),
        .brightBlack: NSColor(calibratedWhite: 0.62, alpha: 1),
        .brightRed: .systemRed,
        .brightGreen: .systemGreen,
        .brightYellow: .systemYellow,
        .brightBlue: .systemBlue,
        .brightMagenta: .systemPink,
        .brightCyan: .systemTeal,
        .brightWhite: .white
    ]

    private static let systemANSIColors: [TerminalANSIColor: NSColor] = [
        .black: adaptiveColor(
            light: .black,
            dark: darkReadableBlack
        ),
        .red: .systemRed,
        .green: .systemGreen,
        .yellow: .systemYellow,
        .blue: adaptiveColor(
            light: .systemBlue,
            dark: darkReadableBlue
        ),
        .magenta: .systemPurple,
        .cyan: .systemCyan,
        .white: adaptiveColor(
            light: NSColor(calibratedWhite: 0.35, alpha: 1),
            dark: NSColor(calibratedWhite: 0.9, alpha: 1)
        ),
        .brightBlack: adaptiveColor(
            light: .systemGray,
            dark: NSColor(calibratedWhite: 0.62, alpha: 1)
        ),
        .brightRed: .systemRed,
        .brightGreen: .systemGreen,
        .brightYellow: .systemYellow,
        .brightBlue: .systemBlue,
        .brightMagenta: .systemPink,
        .brightCyan: .systemTeal,
        .brightWhite: adaptiveColor(
            light: NSColor(calibratedWhite: 0.55, alpha: 1),
            dark: .white
        )
    ]

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return dark
            }

            return light
        }
    }
}
