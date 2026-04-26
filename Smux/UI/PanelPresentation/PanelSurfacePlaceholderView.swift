import SwiftUI

struct PanelSurfacePlaceholderView: View {
    var surface: PanelSurfaceDescriptor
    var isFocused: Bool
    var selectedDocumentURL: URL?
    var onSplit: (SplitDirection) -> Void
    var onCreateTerminal: () -> Void = {}
    var onOpenSelectedDocument: (DocumentOpenMode) -> Void = { _ in }

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
                .fill(isFocused ? Color.accentColor.opacity(0.035) : Color.clear)
                .padding(4)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFocused ? Color(nsColor: .separatorColor).opacity(0.28) : Color.clear, lineWidth: 1)
                .padding(4)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                placeholderActionButton(
                    title: "Terminal",
                    systemImage: "terminal",
                    isEnabled: true
                ) {
                    onCreateTerminal()
                }

                placeholderActionButton(
                    title: "Editor",
                    systemImage: "doc.text",
                    isEnabled: selectedDocumentURL != nil
                ) {
                    onOpenSelectedDocument(.editor)
                }

                placeholderActionButton(
                    title: "Preview",
                    systemImage: "eye",
                    isEnabled: selectedDocumentURL != nil
                ) {
                    onOpenSelectedDocument(.preview)
                }
            }

            HStack(spacing: 8) {
                placeholderActionButton(
                    title: "Split Right",
                    systemImage: "rectangle.split.2x1",
                    isEnabled: true
                ) {
                    onSplit(.horizontal)
                }

                placeholderActionButton(
                    title: "Split Down",
                    systemImage: "rectangle.split.1x2",
                    isEnabled: true
                ) {
                    onSplit(.vertical)
                }
            }
        }
        .frame(maxWidth: 360)
    }

    private func placeholderActionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .frame(width: 15)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .frame(minWidth: 92)
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(Color.primary)
        .opacity(isEnabled ? 1 : 0.45)
        .help(title)
    }
}
