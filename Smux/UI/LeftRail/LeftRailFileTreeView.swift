import SwiftUI

struct LeftRailFileTreeView: View {
    var rootNode: FileTreeNode
    var selectedNodeID: FileTreeNode.ID?
    var onExpand: (FileTreeNode.ID) -> Void
    var onSelect: (FileTreeNode.ID) -> Void

    var body: some View {
        ScrollView {
            LeftRailFileTreeRow(
                node: rootNode,
                depth: 0,
                selectedNodeID: selectedNodeID,
                onExpand: onExpand,
                onSelect: onSelect
            )
        }
        .frame(maxHeight: 260, alignment: .topLeading)
    }
}

nonisolated struct LeftRailFileTreeNodePresentation: Equatable {
    enum Emphasis: Equatable {
        case standard
        case documentCandidate
    }

    var systemImage: String
    var emphasis: Emphasis
    var showsDisclosure: Bool
    var childrenStatusText: String?

    init(node: FileTreeNode) {
        showsDisclosure = node.kind == .directory

        switch node.kind {
        case .directory:
            systemImage = "folder"
            emphasis = .standard
        case .file:
            systemImage = node.isDocumentCandidate ? "doc.richtext" : "doc"
            emphasis = node.isDocumentCandidate ? .documentCandidate : .standard
        }

        switch node.childrenState {
        case .failed:
            childrenStatusText = "Unable to load"
        case .loading:
            childrenStatusText = "Loading"
        case .loaded, .notLoaded:
            childrenStatusText = nil
        }
    }
}

private struct LeftRailFileTreeRow: View {
    var node: FileTreeNode
    var depth: Int
    var selectedNodeID: FileTreeNode.ID?
    var onExpand: (FileTreeNode.ID) -> Void
    var onSelect: (FileTreeNode.ID) -> Void

    @State private var isHovered = false

    private var presentation: LeftRailFileTreeNodePresentation {
        LeftRailFileTreeNodePresentation(node: node)
    }

    private var isSelected: Bool {
        selectedNodeID == node.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                disclosureButton

                Button {
                    onSelect(node.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: presentation.systemImage)
                            .frame(width: 14)
                            .foregroundStyle(iconStyle)

                        Text(node.name)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? .primary : .secondary)

                        Spacer(minLength: 6)

                        if let childrenStatusText = presentation.childrenStatusText {
                            Text(childrenStatusText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .padding(.leading, CGFloat(depth) * 14)
            .background(LeftRailRowBackground(isActive: isSelected, isHovered: isHovered))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onHover { hovering in
                isHovered = hovering
            }

            ForEach(loadedChildren) { child in
                LeftRailFileTreeRow(
                    node: child,
                    depth: depth + 1,
                    selectedNodeID: selectedNodeID,
                    onExpand: onExpand,
                    onSelect: onSelect
                )
            }
        }
    }

    @ViewBuilder
    private var disclosureButton: some View {
        if presentation.showsDisclosure {
            Button {
                onExpand(node.id)
            } label: {
                Image(systemName: disclosureSystemImage)
                    .frame(width: 10)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            Spacer()
                .frame(width: 10)
        }
    }

    private var disclosureSystemImage: String {
        switch node.childrenState {
        case .loaded:
            "chevron.down"
        case .loading:
            "hourglass"
        case .failed, .notLoaded:
            "chevron.right"
        }
    }

    private var loadedChildren: [FileTreeNode] {
        guard case .loaded(let children) = node.childrenState else {
            return []
        }

        return children
    }

    private var iconStyle: HierarchicalShapeStyle {
        switch presentation.emphasis {
        case .standard:
            .secondary
        case .documentCandidate:
            .primary
        }
    }

}
