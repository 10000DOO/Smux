import Combine
import Foundation

@MainActor
final class PanelStore: ObservableObject, PanelCommanding {
    @Published var rootNode: PanelNode = .placeholder
    @Published var focusedPanelID: PanelNode.ID?

    init(rootNode: PanelNode = .placeholder, focusedPanelID: PanelNode.ID? = nil) {
        self.rootNode = rootNode
        self.focusedPanelID = focusedPanelID ?? rootNode.firstLeafID
    }

    func focus(panelID: PanelNode.ID?) {
        guard let panelID else {
            focusedPanelID = nil
            return
        }

        guard rootNode.containsLeaf(panelID: panelID) else {
            return
        }

        focusedPanelID = panelID
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        guard let targetPanelID = focusedPanelID ?? rootNode.firstLeafID else {
            return
        }

        guard let result = rootNode.splittingLeaf(
            panelID: targetPanelID,
            direction: direction,
            newSurface: surface
        ) else {
            return
        }

        rootNode = result.node
        focusedPanelID = result.newPanelID
    }

    func replaceFocusedPanel(with surface: PanelSurfaceDescriptor) {
        guard let targetPanelID = focusedPanelID ?? rootNode.firstLeafID else {
            return
        }

        guard rootNode.containsLeaf(panelID: targetPanelID) else {
            return
        }

        rootNode = rootNode.replacingSurface(panelID: targetPanelID, with: surface)
        focusedPanelID = targetPanelID
    }

    func reset(to rootNode: PanelNode = .placeholder) {
        self.rootNode = rootNode
        focusedPanelID = rootNode.firstLeafID
    }
}
