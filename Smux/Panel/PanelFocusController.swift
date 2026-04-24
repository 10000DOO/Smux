import Combine
import Foundation

@MainActor
final class PanelFocusController: ObservableObject {
    @Published var focusedPanelID: PanelNode.ID?

    func focus(panelID: PanelNode.ID?) {}
}
