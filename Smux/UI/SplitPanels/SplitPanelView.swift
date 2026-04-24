import SwiftUI

struct SplitPanelView: View {
    var node: PanelNode
    var focusedPanelID: PanelNode.ID?
    var onFocus: (PanelNode.ID) -> Void
    var onReplaceSurface: (PanelNode.ID, PanelSurfaceDescriptor) -> Void
    var onSplit: (PanelNode.ID, SplitDirection) -> Void

    var body: some View {
        switch node.kind {
        case .leaf:
            surfaceView(node.surface ?? .empty, panelID: node.id)
        case .split:
            splitView
        }
    }

    @ViewBuilder
    private var splitView: some View {
        switch node.direction {
        case .horizontal:
            HStack(spacing: 1) {
                ForEach(node.children) { child in
                    SplitPanelView(
                        node: child,
                        focusedPanelID: focusedPanelID,
                        onFocus: onFocus,
                        onReplaceSurface: onReplaceSurface,
                        onSplit: onSplit
                    )
                }
            }
        case .vertical:
            VStack(spacing: 1) {
                ForEach(node.children) { child in
                    SplitPanelView(
                        node: child,
                        focusedPanelID: focusedPanelID,
                        onFocus: onFocus,
                        onReplaceSurface: onReplaceSurface,
                        onSplit: onSplit
                    )
                }
            }
        case nil:
            surfaceView(.empty, panelID: node.id)
        }
    }

    @ViewBuilder
    private func surfaceView(_ surface: PanelSurfaceDescriptor, panelID: PanelNode.ID) -> some View {
        PanelSurfacePlaceholderView(
            surface: surface,
            isFocused: focusedPanelID == panelID,
            onReplaceSurface: { replacement in
                onReplaceSurface(panelID, replacement)
            },
            onSplit: { direction in
                onSplit(panelID, direction)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus(panelID)
        }
    }
}
