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

    func createPanel(splitDirection: SplitDirection, surface: PanelSurfaceDescriptor) {
        splitFocusedPanel(direction: splitDirection, surface: surface)
    }

    var canCloseFocusedPanel: Bool {
        rootNode.leafIDs.count >= 2 || (focusedSurface.map { $0 != .empty } ?? false)
    }

    var focusedSurface: PanelSurfaceDescriptor? {
        rootNode.surface(forLeaf: focusedCommandPanelID)
    }

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {
        guard let targetPanelID = focusedPanelID ?? rootNode.firstLeafID else {
            return
        }

        splitPanel(panelID: targetPanelID, direction: direction, surface: surface)
    }

    func replaceFocusedPanel(with surface: PanelSurfaceDescriptor) {
        guard let targetPanelID = focusedPanelID ?? rootNode.firstLeafID else {
            return
        }

        replacePanel(panelID: targetPanelID, with: surface)
    }

    func focusNextPanel() {
        focusPanel(offset: 1, fallbackToLast: false)
    }

    func focusPreviousPanel() {
        focusPanel(offset: -1, fallbackToLast: true)
    }

    func closeFocusedPanel() {
        guard let targetPanelID = focusedCommandPanelID else {
            return
        }

        closePanel(panelID: targetPanelID)
    }

    func splitPanel(
        panelID: PanelNode.ID,
        direction: SplitDirection,
        surface: PanelSurfaceDescriptor
    ) {
        guard let result = rootNode.splittingLeaf(
            panelID: panelID,
            direction: direction,
            newSurface: surface
        ) else {
            return
        }

        rootNode = result.node
        focusedPanelID = result.newPanelID
    }

    func replacePanel(panelID: PanelNode.ID, with surface: PanelSurfaceDescriptor) {
        guard rootNode.containsLeaf(panelID: panelID) else {
            return
        }

        rootNode = rootNode.replacingSurface(panelID: panelID, with: surface)
        focusedPanelID = panelID
    }

    func closePanel(panelID: PanelNode.ID) {
        guard rootNode.containsLeaf(panelID: panelID) else {
            return
        }

        if rootNode.isLeaf {
            rootNode = .leaf(surface: .empty)
            focusedPanelID = rootNode.id
            return
        }

        guard let result = rootNode.removingLeaf(panelID: panelID) else {
            return
        }

        rootNode = result.node
        focusedPanelID = result.focusCandidateID ?? rootNode.firstLeafID
    }

    func updateSplitRatio(splitID: PanelNode.ID, ratio: Double) {
        guard let updatedRootNode = rootNode.updatingSplitRatio(
            splitID: splitID,
            ratio: ratio
        ) else {
            return
        }

        rootNode = updatedRootNode
    }

    func reset(to rootNode: PanelNode = .placeholder) {
        self.rootNode = rootNode
        focusedPanelID = rootNode.firstLeafID
    }

    private var focusedCommandPanelID: PanelNode.ID? {
        if let focusedPanelID, rootNode.containsLeaf(panelID: focusedPanelID) {
            return focusedPanelID
        }

        return rootNode.firstLeafID
    }

    private func focusPanel(offset: Int, fallbackToLast: Bool) {
        let leafIDs = rootNode.leafIDs

        guard !leafIDs.isEmpty else {
            focusedPanelID = nil
            return
        }

        guard let focusedPanelID,
              let currentIndex = leafIDs.firstIndex(of: focusedPanelID)
        else {
            let fallbackIndex = fallbackToLast
                ? leafIDs.index(before: leafIDs.endIndex)
                : leafIDs.startIndex
            self.focusedPanelID = leafIDs[fallbackIndex]
            return
        }

        let nextIndex = (currentIndex + offset + leafIDs.count) % leafIDs.count
        self.focusedPanelID = leafIDs[nextIndex]
    }
}
