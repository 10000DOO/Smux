import Combine
import Foundation

@MainActor
final class DocumentEditorViewModel: ObservableObject {
    @Published var session: DocumentSession?
    @Published var text = ""
    @Published var selectedRange: NSRange?

    func load(sessionID: DocumentSession.ID) async throws {}

    func updateText(_ text: String) {}

    func saveNow() async throws {}
}
