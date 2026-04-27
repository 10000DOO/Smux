import SwiftUI

nonisolated enum PanelStartSurfaceDestination: CaseIterable, Hashable {
    case terminal
    case editor
    case preview
}

nonisolated struct PanelStartSurfaceOptionPresentation: Identifiable, Equatable {
    var destination: PanelStartSurfaceDestination
    var title: String
    var systemImage: String
    var isEnabled: Bool

    var id: PanelStartSurfaceDestination {
        destination
    }

    static func primaryOptions(hasSelectedDocument: Bool) -> [PanelStartSurfaceOptionPresentation] {
        [
            PanelStartSurfaceOptionPresentation(
                destination: .terminal,
                title: "Terminal",
                systemImage: "terminal",
                isEnabled: true
            ),
            PanelStartSurfaceOptionPresentation(
                destination: .editor,
                title: "Editor",
                systemImage: "doc.text",
                isEnabled: hasSelectedDocument
            ),
            PanelStartSurfaceOptionPresentation(
                destination: .preview,
                title: "Preview",
                systemImage: "eye",
                isEnabled: hasSelectedDocument
            )
        ]
    }
}

struct PanelStartSurfaceView: View {
    var isFocused: Bool
    var canOpenDocument: Bool
    var onCreateTerminal: () -> Void
    var onOpenEditor: () -> Void
    var onOpenPreview: () -> Void
    var onSplitRight: () -> Void
    var onSplitDown: () -> Void

    var body: some View {
        let options = PanelStartSurfaceOptionPresentation.primaryOptions(hasSelectedDocument: canOpenDocument)

        VStack(spacing: 18) {
            Label("New Panel", systemImage: "plus.square")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(options) { option in
                        startActionButton(option)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(options) { option in
                        startActionButton(option)
                    }
                }
            }

            HStack(spacing: 8) {
                splitActionButton(
                    title: "Split Right",
                    systemImage: "rectangle.split.2x1",
                    action: onSplitRight
                )

                splitActionButton(
                    title: "Split Down",
                    systemImage: "rectangle.split.1x2",
                    action: onSplitDown
                )
            }
        }
        .padding(24)
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
        .accessibilityLabel("New panel")
    }

    private func startActionButton(_ option: PanelStartSurfaceOptionPresentation) -> some View {
        Button {
            perform(option.destination)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.systemImage)
                    .font(.title3)
                    .frame(width: 24, height: 24)
                Text(option.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(width: 96, height: 76)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .opacity(option.isEnabled ? 1 : 0.45)
        .disabled(!option.isEnabled)
        .help(option.isEnabled ? option.title : "Select a document in the sidebar first.")
        .accessibilityLabel(option.title)
    }

    private func splitActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 104)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .help(title)
        .accessibilityLabel(title)
    }

    private func perform(_ destination: PanelStartSurfaceDestination) {
        switch destination {
        case .terminal:
            onCreateTerminal()
        case .editor:
            onOpenEditor()
        case .preview:
            onOpenPreview()
        }
    }
}
