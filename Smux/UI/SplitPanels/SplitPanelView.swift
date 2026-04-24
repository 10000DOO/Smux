import SwiftUI

struct SplitPanelView: View {
    var node: PanelNode

    var body: some View {
        switch node.kind {
        case .leaf:
            surfaceView(node.surface ?? .empty)
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
                    SplitPanelView(node: child)
                }
            }
        case .vertical:
            VStack(spacing: 1) {
                ForEach(node.children) { child in
                    SplitPanelView(node: child)
                }
            }
        case nil:
            surfaceView(.empty)
        }
    }

    @ViewBuilder
    private func surfaceView(_ surface: PanelSurfaceDescriptor) -> some View {
        switch surface {
        case .terminal:
            PlaceholderSurfaceView(title: "Terminal", systemImage: "terminal")
        case .editor:
            PlaceholderSurfaceView(title: "Editor", systemImage: "doc.text")
        case .preview:
            PlaceholderSurfaceView(title: "Preview", systemImage: "eye")
        case .empty:
            PlaceholderSurfaceView(title: "Workspace", systemImage: "rectangle.split.3x1")
        }
    }
}
