import SwiftUI

struct LeftRailSectionView<Content: View, Trailing: View>: View {
    var title: String
    var count: Int?
    var trailing: Trailing
    var content: Content

    init(
        title: String,
        count: Int? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.trailing = trailing()
        self.content = content()
    }

    init(
        title: String,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) where Trailing == EmptyView {
        self.init(title: title, count: count, trailing: EmptyView.init, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                trailing
            }
            .padding(.horizontal, 1)

            content
        }
    }
}

struct LeftRailEmptyLine: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
    }
}
