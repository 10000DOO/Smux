import Foundation

@MainActor
final class AutoSaveCoordinator {
    typealias SaveAction = @MainActor @Sendable (DocumentSession.ID) async throws -> Void

    private let debounceNanoseconds: UInt64
    private let saveAction: SaveAction
    private var scheduledTasks: [DocumentSession.ID: Task<Void, Never>] = [:]
    private var scheduleTokens: [DocumentSession.ID: UUID] = [:]
    private(set) var lastErrors: [DocumentSession.ID: any Error] = [:]

    init(
        debounceInterval: TimeInterval = 1,
        saveAction: @escaping SaveAction = { _ in }
    ) {
        self.debounceNanoseconds = Self.nanoseconds(for: debounceInterval)
        self.saveAction = saveAction
    }

    func scheduleAutosave(for documentID: DocumentSession.ID) {
        cancelAutosave(for: documentID)

        let token = UUID()
        scheduleTokens[documentID] = token

        scheduledTasks[documentID] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()
                try await saveAction(documentID)
                finishScheduledAutosave(documentID: documentID, token: token, error: nil)
            } catch is CancellationError {
                finishScheduledAutosave(documentID: documentID, token: token, error: nil)
            } catch {
                finishScheduledAutosave(documentID: documentID, token: token, error: error)
            }
        }
    }

    func cancelAutosave(for documentID: DocumentSession.ID) {
        scheduledTasks[documentID]?.cancel()
        scheduledTasks[documentID] = nil
        scheduleTokens[documentID] = nil
    }

    func flush(documentID: DocumentSession.ID) async throws {
        cancelAutosave(for: documentID)

        do {
            try await saveAction(documentID)
            lastErrors[documentID] = nil
        } catch {
            lastErrors[documentID] = error
            throw error
        }
    }

    private func finishScheduledAutosave(
        documentID: DocumentSession.ID,
        token: UUID,
        error: (any Error)?
    ) {
        guard scheduleTokens[documentID] == token else {
            return
        }

        scheduledTasks[documentID] = nil
        scheduleTokens[documentID] = nil
        lastErrors[documentID] = error
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        let nanoseconds = max(0, interval) * 1_000_000_000

        guard nanoseconds < Double(UInt64.max) else {
            return UInt64.max
        }

        return UInt64(nanoseconds)
    }
}
