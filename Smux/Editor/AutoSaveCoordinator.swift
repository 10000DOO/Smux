import Foundation

nonisolated enum AutoSaveState: String, Hashable, Sendable {
    case idle
    case scheduled
    case saving
    case saved
    case dirty
    case failed
    case conflicted
    case cancelled
}

nonisolated struct AutoSaveStatus: Hashable, Sendable {
    var documentID: DocumentSession.ID
    var state: AutoSaveState
    var result: DocumentSaveResult?

    var failure: DocumentSaveFailure? {
        result?.failure
    }

    var conflict: DocumentConflict? {
        result?.conflict
    }

    static func idle(documentID: DocumentSession.ID) -> AutoSaveStatus {
        AutoSaveStatus(documentID: documentID, state: .idle, result: nil)
    }

    static func scheduled(documentID: DocumentSession.ID) -> AutoSaveStatus {
        AutoSaveStatus(documentID: documentID, state: .scheduled, result: nil)
    }

    static func saving(documentID: DocumentSession.ID) -> AutoSaveStatus {
        AutoSaveStatus(documentID: documentID, state: .saving, result: nil)
    }

    static func cancelled(documentID: DocumentSession.ID) -> AutoSaveStatus {
        AutoSaveStatus(documentID: documentID, state: .cancelled, result: nil)
    }

    static func completed(
        documentID: DocumentSession.ID,
        result: DocumentSaveResult
    ) -> AutoSaveStatus {
        AutoSaveStatus(
            documentID: documentID,
            state: AutoSaveState(resultState: result.state),
            result: result
        )
    }
}

extension AutoSaveState {
    nonisolated init(resultState: DocumentSaveState) {
        switch resultState {
        case .clean:
            self = .saved
        case .dirty:
            self = .dirty
        case .saving:
            self = .saving
        case .failed:
            self = .failed
        case .conflicted:
            self = .conflicted
        }
    }
}

@MainActor
final class AutoSaveCoordinator {
    typealias SaveAction = @MainActor @Sendable (DocumentSession.ID) async -> DocumentSaveResult

    private let debounceNanoseconds: UInt64
    private let saveAction: SaveAction
    private var scheduledTasks: [DocumentSession.ID: Task<Void, Never>] = [:]
    private var scheduleTokens: [DocumentSession.ID: UUID] = [:]
    private var savingDocumentIDs: Set<DocumentSession.ID> = []
    private(set) var statuses: [DocumentSession.ID: AutoSaveStatus] = [:]

    init(
        debounceInterval: TimeInterval = 1,
        saveAction: @escaping SaveAction = { documentID in .saved(documentID: documentID) }
    ) {
        self.debounceNanoseconds = Self.nanoseconds(for: debounceInterval)
        self.saveAction = saveAction
    }

    func scheduleAutosave(for documentID: DocumentSession.ID) {
        cancelScheduledAutosave(for: documentID, markCancelled: false)

        let token = UUID()
        scheduleTokens[documentID] = token
        statuses[documentID] = .scheduled(documentID: documentID)

        scheduledTasks[documentID] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()

                guard scheduleTokens[documentID] == token else {
                    return
                }

                scheduledTasks[documentID] = nil
                scheduleTokens[documentID] = nil
                await save(documentID: documentID)
            } catch {
                finishCancelledAutosave(documentID: documentID, token: token)
            }
        }
    }

    @discardableResult
    func cancelAutosave(for documentID: DocumentSession.ID) -> AutoSaveStatus {
        cancelScheduledAutosave(for: documentID, markCancelled: true)
    }

    func status(for documentID: DocumentSession.ID) -> AutoSaveStatus {
        statuses[documentID] ?? .idle(documentID: documentID)
    }

    @discardableResult
    func save(documentID: DocumentSession.ID) async -> DocumentSaveResult {
        cancelScheduledAutosave(for: documentID, markCancelled: false)

        guard !savingDocumentIDs.contains(documentID) else {
            let result = DocumentSaveResult.failed(
                documentID: documentID,
                failure: DocumentSaveFailure(documentEditorError: .saveAlreadyInProgress)
            )
            statuses[documentID] = .completed(documentID: documentID, result: result)

            return result
        }

        savingDocumentIDs.insert(documentID)
        statuses[documentID] = .saving(documentID: documentID)
        let result = await saveAction(documentID)
        savingDocumentIDs.remove(documentID)
        statuses[documentID] = .completed(documentID: documentID, result: result)

        return result
    }

    @discardableResult
    func flush(documentID: DocumentSession.ID) async -> DocumentSaveResult {
        await save(documentID: documentID)
    }

    @discardableResult
    private func cancelScheduledAutosave(
        for documentID: DocumentSession.ID,
        markCancelled: Bool
    ) -> AutoSaveStatus {
        guard let scheduledTask = scheduledTasks[documentID] else {
            return status(for: documentID)
        }

        scheduledTask.cancel()
        scheduledTasks[documentID] = nil
        scheduleTokens[documentID] = nil

        if markCancelled {
            statuses[documentID] = .cancelled(documentID: documentID)
        }

        return status(for: documentID)
    }

    private func finishCancelledAutosave(documentID: DocumentSession.ID, token: UUID) {
        guard scheduleTokens[documentID] == token else {
            return
        }

        scheduledTasks[documentID] = nil
        scheduleTokens[documentID] = nil
        statuses[documentID] = .cancelled(documentID: documentID)
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        let nanoseconds = max(0, interval) * 1_000_000_000

        guard nanoseconds < Double(UInt64.max) else {
            return UInt64.max
        }

        return UInt64(nanoseconds)
    }
}
