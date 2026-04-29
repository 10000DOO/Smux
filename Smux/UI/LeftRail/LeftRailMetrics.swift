import SwiftUI

nonisolated enum LeftRailLayoutMetrics {
    static let collapsedWidth: CGFloat = 54
    static let defaultExpandedWidth: CGFloat = 300
    static let minimumExpandedWidth: CGFloat = 220
    static let maximumExpandedWidth: CGFloat = 420
    static let rowCornerRadius: CGFloat = 7
    static let sectionSpacing: CGFloat = 14

    static func clampedExpandedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumExpandedWidth), maximumExpandedWidth)
    }

    static func width(isCollapsed: Bool, expandedWidth: CGFloat) -> CGFloat {
        isCollapsed ? collapsedWidth : clampedExpandedWidth(expandedWidth)
    }

    static func resizePreviewWidth(startWidth: CGFloat, translation: CGFloat) -> CGFloat {
        clampedExpandedWidth(startWidth + translation)
    }
}

struct LeftRailRowBackground: View {
    var isActive: Bool
    var isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: LeftRailLayoutMetrics.rowCornerRadius, style: .continuous)
            .fill(backgroundStyle)
    }

    private var backgroundStyle: Color {
        if isActive {
            return Color.primary.opacity(0.095)
        }

        if isHovered {
            return Color.primary.opacity(0.055)
        }

        return .clear
    }
}

struct LeftRailLeadingIndicator: View {
    var isActive: Bool

    var body: some View {
        Capsule()
            .fill(isActive ? Color.accentColor : Color.clear)
            .frame(width: 3)
    }
}

struct LeftRailBadge: View {
    var count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, count > 9 ? 4 : 0)
                .background(Color.red, in: Capsule())
        }
    }
}

struct LeftRailCompactBadge: View {
    var count: Int

    var body: some View {
        if count > 0 {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .offset(x: 1, y: -1)
        }
    }
}
