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

    func color(for textColor: TerminalTextColor?) -> NSColor? {
        guard let textColor else {
            return nil
        }

        switch textColor {
        case let .ansi(ansiColor):
            return ansi[ansiColor]
        case let .indexed(index):
            return colorFor256ColorIndex(index)
        case let .rgb(red, green, blue):
            return NSColor(
                calibratedRed: CGFloat(min(max(red, 0), 255)) / 255,
                green: CGFloat(min(max(green, 0), 255)) / 255,
                blue: CGFloat(min(max(blue, 0), 255)) / 255,
                alpha: 1
            )
        }
    }

    var ansiColorsInTerminalOrder: [NSColor] {
        (0...15).map { rawValue in
            guard let ansiColor = TerminalANSIColor(rawValue: rawValue) else {
                return foreground
            }

            return ansi[ansiColor] ?? foreground
        }
    }

    private func colorFor256ColorIndex(_ index: Int) -> NSColor? {
        switch index {
        case 0...15:
            guard let ansiColor = TerminalANSIColor(rawValue: index) else {
                return nil
            }

            return ansi[ansiColor]
        case 16...231:
            let colorIndex = index - 16
            let red = colorIndex / 36
            let green = (colorIndex % 36) / 6
            let blue = colorIndex % 6
            return NSColor(
                calibratedRed: colorCubeComponent(red),
                green: colorCubeComponent(green),
                blue: colorCubeComponent(blue),
                alpha: 1
            )
        case 232...255:
            let component = CGFloat(8 + (index - 232) * 10) / 255
            return NSColor(calibratedWhite: component, alpha: 1)
        default:
            return nil
        }
    }

    private func colorCubeComponent(_ component: Int) -> CGFloat {
        component == 0 ? 0 : CGFloat(55 + component * 40) / 255
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
