import Combine
import Foundation

@MainActor
final class PanelStore: ObservableObject, PanelCommanding {
    @Published var rootNode: PanelNode = .placeholder
    @Published var focusedPanelID: PanelNode.ID?

    func splitFocusedPanel(direction: SplitDirection, surface: PanelSurfaceDescriptor) {}

    func replaceFocusedPanel(with surface: PanelSurfaceDescriptor) {}
}
