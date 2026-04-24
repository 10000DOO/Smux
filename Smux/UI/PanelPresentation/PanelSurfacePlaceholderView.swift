import SwiftUI

struct PanelSurfacePlaceholderView: View {
    var surface: PanelSurfaceDescriptor
    var isFocused: Bool
    var onReplaceSurface: (PanelSurfaceDescriptor) -> Void
    var onSplit: (SplitDirection) -> Void

    var body: some View {
        let presentation = PanelSurfacePresentation(surface: surface)

        VStack(spacing: 14) {
            PlaceholderSurfaceView(
                title: presentation.title,
                systemImage: presentation.systemImage
            )

            actionButtons
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(4)
        }
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onReplaceSurface(.terminal(sessionID: UUID()))
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }

                Button {
                    onReplaceSurface(.editor(documentID: UUID()))
                } label: {
                    Label("Editor", systemImage: "doc.text")
                }

                Button {
                    onReplaceSurface(.preview(previewID: UUID()))
                } label: {
                    Label("Preview", systemImage: "eye")
                }
            }

            HStack(spacing: 8) {
                Button {
                    onSplit(.horizontal)
                } label: {
                    Label("Split H", systemImage: "rectangle.split.2x1")
                }

                Button {
                    onSplit(.vertical)
                } label: {
                    Label("Split V", systemImage: "rectangle.split.1x2")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
