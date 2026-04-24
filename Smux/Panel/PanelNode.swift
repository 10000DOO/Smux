import Foundation

enum PanelNodeKind: String, Codable, Hashable {
    case leaf
    case split
}

enum SplitDirection: String, Codable, Hashable {
    case horizontal
    case vertical
}

enum PanelSurfaceDescriptor: Codable, Hashable {
    case terminal(sessionID: TerminalSession.ID)
    case editor(documentID: DocumentSession.ID)
    case preview(previewID: PreviewState.ID)
    case empty
}

struct PanelNode: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var kind: PanelNodeKind
    var direction: SplitDirection?
    var ratio: Double?
    var children: [PanelNode]
    var surface: PanelSurfaceDescriptor?
}

extension PanelNode {
    static let placeholder = PanelNode(
        id: UUID(),
        kind: .leaf,
        direction: nil,
        ratio: nil,
        children: [],
        surface: .empty
    )
}
