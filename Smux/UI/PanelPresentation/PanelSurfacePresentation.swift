import Foundation

nonisolated struct PanelSurfacePresentation: Hashable {
    var title: String
    var systemImage: String
    var accessibilityLabel: String

    init(surface: PanelSurfaceDescriptor) {
        switch surface {
        case .terminal:
            title = "Terminal"
            systemImage = "terminal"
        case .editor:
            title = "Editor"
            systemImage = "doc.text"
        case .preview:
            title = "Preview"
            systemImage = "eye"
        case .empty:
            title = "Workspace"
            systemImage = "rectangle.split.3x1"
        }

        accessibilityLabel = "\(title) panel surface"
    }
}
