import Foundation

nonisolated struct PanelLeafSummary: Identifiable, Hashable {
    var id: PanelNode.ID
    var surface: PanelSurfaceDescriptor
    var isFocused: Bool
}

extension PanelNode {
    func leafSummaries(focusedPanelID: PanelNode.ID?) -> [PanelLeafSummary] {
        if isLeaf {
            return [
                PanelLeafSummary(
                    id: id,
                    surface: surface ?? .empty,
                    isFocused: focusedPanelID == id
                )
            ]
        }

        return children.flatMap { $0.leafSummaries(focusedPanelID: focusedPanelID) }
    }

    var leafCount: Int {
        leafSummaries(focusedPanelID: nil).count
    }
}
