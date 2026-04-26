import Foundation

nonisolated enum TerminalCellWidth {
    static func width(of character: Character) -> Int {
        character.unicodeScalars.contains(where: isWideScalar) ? 2 : 1
    }

    private static func isWideScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F000...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
