import Foundation

nonisolated struct PanelSurfacePresentation: Hashable {
    var title: String
    var systemImage: String
    var accessibilityLabel: String

    init(surface: PanelSurfaceDescriptor) {
        switch surface {
        case .session:
            title = "Session"
            systemImage = "rectangle.inset.filled"
        case .empty:
            title = "Workspace"
            systemImage = "rectangle.split.3x1"
        }

        accessibilityLabel = "\(title) panel surface"
    }

    init(session: WorkspaceSession) {
        switch session.kind {
        case .terminal:
            title = session.title.isEmpty ? "Terminal" : session.title
            systemImage = "terminal"
        case .editor:
            title = session.title.isEmpty ? "Editor" : session.title
            systemImage = "doc.text"
        case .preview:
            title = session.title.isEmpty ? "Preview" : session.title
            systemImage = "eye"
        }

        accessibilityLabel = "\(title) session"
    }
}
