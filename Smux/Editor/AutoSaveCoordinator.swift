import Foundation

@MainActor
final class AutoSaveCoordinator {
    func scheduleAutosave(for documentID: DocumentSession.ID) {}

    func cancelAutosave(for documentID: DocumentSession.ID) {}

    func flush(documentID: DocumentSession.ID) async throws {}
}
