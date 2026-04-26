import Combine
import Foundation

@MainActor
final class DocumentEditorViewModel: ObservableObject {
    @Published var session: DocumentSession?
    @Published var text = ""
    @Published var selectedRange: NSRange?
    @Published private(set) var lastSaveResult: DocumentSaveResult?
    @Published private(set) var autoSaveStatus: AutoSaveStatus?

    private let sessionStore: any DocumentSessionStoring
    private let fileIO: any DocumentFileIO
    private let autoSaveDebounceInterval: TimeInterval
    private var savingSessionIDs: Set<DocumentSession.ID> = []
    private var pendingFileWatchEventsAfterSave: [DocumentSession.ID: FileWatchEvent] = [:]
    private lazy var autoSaveCoordinator = AutoSaveCoordinator(
        debounceInterval: autoSaveDebounceInterval,
        saveAction: { [weak self] documentID in
            guard let self else {
                return DocumentSaveResult.failed(
                    documentID: documentID,
                    failure: DocumentSaveFailure(documentEditorError: .missingSession)
                )
            }

            return await self.saveAutosaveSession(documentID: documentID)
        },
        statusDidChange: { [weak self] status in
            self?.autoSaveStatus = status
        }
    )

    init(
        sessionStore: any DocumentSessionStoring = DocumentSessionStore(),
        fileIO: any DocumentFileIO = FileBackedDocumentFileIO(),
        autoSaveDebounceInterval: TimeInterval = 1
    ) {
        self.sessionStore = sessionStore
        self.fileIO = fileIO
        self.autoSaveDebounceInterval = autoSaveDebounceInterval
    }

    func load(sessionID: DocumentSession.ID) async throws {
        guard var loadedSession = sessionStore.session(for: sessionID) else {
            throw DocumentEditorError.sessionNotFound(sessionID)
        }

        let loadedDocument = try await fileIO.loadText(from: loadedSession.url)
        loadedSession.language = DocumentLanguage.detect(for: loadedSession.url)
        loadedSession.fileFingerprint = loadedDocument.fingerprint
        loadedSession.isDirty = false
        loadedSession.saveState = .clean
        loadedSession.conflict = nil
        loadedSession.externalChange = nil

        text = loadedDocument.text
        selectedRange = NSRange(location: 0, length: 0)
        lastSaveResult = nil
        autoSaveStatus = .idle(documentID: loadedSession.id)
        session = loadedSession
        sessionStore.upsertSession(loadedSession)
    }

    func load(session: DocumentSession) async throws {
        sessionStore.upsertSession(session)
        try await load(sessionID: session.id)
    }

    func updateText(_ updatedText: String) {
        guard updatedText != text else {
            return
        }

        text = updatedText

        guard var currentSession = session else {
            return
        }

        currentSession.textVersion += 1
        currentSession.isDirty = true
        if currentSession.externalChange == nil {
            currentSession.saveState = .dirty
            currentSession.conflict = nil
            lastSaveResult = nil
        } else {
            currentSession.saveState = .conflicted
        }

        session = currentSession
        sessionStore.upsertSession(currentSession)
    }

    @discardableResult
    func handleExternalFileEvent(_ event: FileWatchEvent) async -> Bool {
        guard let currentSession = session, event.scope == .openFile(currentSession.url) else {
            return false
        }

        guard !savingSessionIDs.contains(currentSession.id) else {
            pendingFileWatchEventsAfterSave[currentSession.id] = event
            return false
        }

        return await processExternalFileEvent(event)
    }

    @discardableResult
    private func processExternalFileEvent(_ event: FileWatchEvent) async -> Bool {
        switch event.kind {
        case .deleted:
            return await handleExternalDiskChange(event, missingFileKind: .deleted)
        case .renamed:
            return await handleExternalDiskChange(event, missingFileKind: .renamed)
        case .contentsChanged, .modified, .metadataChanged:
            return await handleExternalDiskChange(event, missingFileKind: .deleted)
        }
    }

    @discardableResult
    func reloadExternalChangeFromDisk(allowDiscardingLocalEdits: Bool = false) async -> Bool {
        guard let currentSession = session else {
            return false
        }

        guard !currentSession.isDirty || allowDiscardingLocalEdits else {
            let result = DocumentSaveResult.failed(
                documentID: currentSession.id,
                failure: DocumentSaveFailure(
                    kind: .conflicted,
                    message: "Reload would discard local edits."
                )
            )
            lastSaveResult = result
            autoSaveStatus = .completed(documentID: currentSession.id, result: result)
            return false
        }

        do {
            let loadedDocument = try await fileIO.loadText(from: currentSession.url)

            guard var latestSession = session, latestSession.id == currentSession.id else {
                return false
            }

            latestSession.language = DocumentLanguage.detect(for: latestSession.url)
            latestSession.textVersion += 1
            latestSession.fileFingerprint = loadedDocument.fingerprint
            latestSession.isDirty = false
            latestSession.saveState = .clean
            latestSession.conflict = nil
            latestSession.externalChange = nil

            text = loadedDocument.text
            selectedRange = NSRange(location: 0, length: 0)
            lastSaveResult = nil
            autoSaveStatus = .idle(documentID: latestSession.id)
            session = latestSession
            sessionStore.upsertSession(latestSession)

            return true
        } catch {
            markReloadFailure(error, documentID: currentSession.id)
            return false
        }
    }

    private func handleExternalDiskChange(
        _ event: FileWatchEvent,
        missingFileKind: DocumentExternalChangeKind
    ) async -> Bool {
        guard let currentSession = session else {
            return false
        }

        do {
            let diskFingerprint = try await fileIO.fingerprint(for: currentSession.url)

            guard let latestSession = session, latestSession.id == currentSession.id else {
                return false
            }

            guard diskFingerprint != latestSession.fileFingerprint else {
                return false
            }

            guard !latestSession.isDirty else {
                markExternalChange(kind: .modified, event: event, currentFingerprint: diskFingerprint)
                return false
            }

            return await reloadExternalChangeFromDisk()
        } catch {
            if !fileIO.fileExists(at: currentSession.url) {
                markExternalChange(kind: missingFileKind, event: event, currentFingerprint: nil)
            } else {
                markReloadFailure(error, documentID: currentSession.id)
            }

            return false
        }
    }

    func updateSelectedRange(_ selectedRange: NSRange?) {
        self.selectedRange = selectedRange
    }

    @discardableResult
    func scheduleAutosave() -> AutoSaveStatus? {
        guard let documentID = session?.id else {
            return nil
        }

        return autoSaveCoordinator.scheduleAutosave(for: documentID)
    }

    @discardableResult
    func cancelAutosave() -> AutoSaveStatus? {
        guard let documentID = session?.id else {
            return nil
        }

        return autoSaveCoordinator.cancelAutosave(for: documentID)
    }

    @discardableResult
    func flushAutosave() async -> DocumentSaveResult {
        guard let documentID = session?.id else {
            let result = DocumentSaveResult.failed(
                documentID: nil,
                failure: DocumentSaveFailure(documentEditorError: .missingSession)
            )
            lastSaveResult = result

            return result
        }

        return await autoSaveCoordinator.flush(documentID: documentID)
    }

    func saveNow() async throws {
        discardPendingAutosave()
        let outcome = await saveCurrentSession()
        lastSaveResult = outcome.result

        if let error = outcome.error {
            throw error
        }
    }

    func saveNowResult() async -> DocumentSaveResult {
        discardPendingAutosave()
        let outcome = await saveCurrentSession()
        lastSaveResult = outcome.result

        return outcome.result
    }

    private func discardPendingAutosave() {
        guard let documentID = session?.id else {
            return
        }

        autoSaveCoordinator.discardScheduledAutosave(for: documentID)
    }

    private func saveAutosaveSession(documentID: DocumentSession.ID) async -> DocumentSaveResult {
        let outcome = await saveCurrentSession(documentID: documentID)
        lastSaveResult = outcome.result

        return outcome.result
    }

    private func markExternalChange(
        kind: DocumentExternalChangeKind,
        event: FileWatchEvent,
        currentFingerprint: FileFingerprint?
    ) {
        guard var currentSession = session else {
            return
        }

        let detectedAt = Date()
        let conflict = DocumentConflict(
            detectedAt: detectedAt,
            loadedFingerprint: currentSession.fileFingerprint,
            currentFingerprint: currentFingerprint
        )
        let externalChange = DocumentExternalChange(
            kind: kind,
            detectedAt: detectedAt,
            url: event.url,
            fileFingerprint: currentFingerprint
        )

        discardPendingAutosave()
        currentSession.isDirty = true
        currentSession.saveState = .conflicted
        currentSession.conflict = conflict
        currentSession.externalChange = externalChange

        let result = DocumentSaveResult.conflicted(documentID: currentSession.id, conflict: conflict)
        lastSaveResult = result
        autoSaveStatus = .completed(documentID: currentSession.id, result: result)
        session = currentSession
        sessionStore.upsertSession(currentSession)
    }

    private func markReloadFailure(_ error: any Error, documentID: DocumentSession.ID) {
        guard var failedSession = sessionStore.session(for: documentID) else {
            return
        }

        failedSession.isDirty = true
        failedSession.saveState = .failed

        if session?.id == documentID {
            session = failedSession
        }
        sessionStore.upsertSession(failedSession)

        let result = DocumentSaveResult.failed(
            documentID: documentID,
            failure: DocumentSaveFailure(error: error)
        )
        lastSaveResult = result
        autoSaveStatus = .completed(documentID: documentID, result: result)
    }

    private func saveCurrentSession(
        documentID expectedDocumentID: DocumentSession.ID? = nil
    ) async -> (result: DocumentSaveResult, error: (any Error)?) {
        guard var currentSession = session else {
            return (
                DocumentSaveResult.failed(
                    documentID: expectedDocumentID,
                    failure: DocumentSaveFailure(documentEditorError: .missingSession)
                ),
                DocumentEditorError.missingSession
            )
        }

        if let expectedDocumentID, currentSession.id != expectedDocumentID {
            return (
                DocumentSaveResult.failed(
                    documentID: expectedDocumentID,
                    failure: DocumentSaveFailure(documentEditorError: .sessionNotFound(expectedDocumentID))
                ),
                DocumentEditorError.sessionNotFound(expectedDocumentID)
            )
        }

        guard !savingSessionIDs.contains(currentSession.id) else {
            return (
                DocumentSaveResult.failed(
                    documentID: currentSession.id,
                    failure: DocumentSaveFailure(documentEditorError: .saveAlreadyInProgress)
                ),
                DocumentEditorError.saveAlreadyInProgress
            )
        }
        savingSessionIDs.insert(currentSession.id)

        let saveText = text
        let savedTextVersion = currentSession.textVersion
        let loadedFingerprint = currentSession.fileFingerprint

        currentSession.saveState = .saving
        session = currentSession
        sessionStore.upsertSession(currentSession)

        do {
            let fingerprint = try await fileIO.saveText(
                saveText,
                to: currentSession.url,
                replacing: loadedFingerprint
            )
            var latestSession = session?.id == currentSession.id
                ? session ?? currentSession
                : sessionStore.session(for: currentSession.id) ?? currentSession
            latestSession.fileFingerprint = fingerprint
            latestSession.conflict = nil
            latestSession.externalChange = nil

            if latestSession.textVersion == savedTextVersion {
                latestSession.isDirty = false
                latestSession.saveState = .clean
            } else {
                latestSession.isDirty = true
                latestSession.saveState = .dirty
            }

            if session?.id == currentSession.id {
                session = latestSession
            }
            sessionStore.upsertSession(latestSession)

            savingSessionIDs.remove(currentSession.id)
            if let pendingOutcome = await processPendingFileWatchEventAfterSave(
                for: currentSession.id
            ) {
                return pendingOutcome
            }

            if latestSession.saveState == .clean {
                return (DocumentSaveResult.saved(documentID: currentSession.id), nil)
            }

            return (DocumentSaveResult.dirty(documentID: currentSession.id), nil)
        } catch let conflictError as DocumentFileWriteConflict {
            let conflict = markSaveConflict(
                currentSession: currentSession,
                loadedFingerprint: conflictError.loadedFingerprint,
                currentFingerprint: conflictError.currentFingerprint
            )
            savingSessionIDs.remove(currentSession.id)
            if let pendingOutcome = await processPendingFileWatchEventAfterSave(for: currentSession.id) {
                return pendingOutcome
            }

            return (
                DocumentSaveResult.conflicted(documentID: currentSession.id, conflict: conflict),
                DocumentEditorError.conflicted(conflict)
            )
        } catch {
            var failedSession = session?.id == currentSession.id
                ? session ?? currentSession
                : sessionStore.session(for: currentSession.id) ?? currentSession
            failedSession.isDirty = true
            failedSession.saveState = .failed

            if session?.id == currentSession.id {
                session = failedSession
            }
            sessionStore.upsertSession(failedSession)
            savingSessionIDs.remove(currentSession.id)
            let failedOutcome = (
                DocumentSaveResult.failed(
                    documentID: currentSession.id,
                    failure: DocumentSaveFailure(error: error)
                ),
                error as (any Error)?
            )

            return await processPendingFileWatchEventAfterSave(for: currentSession.id) ?? failedOutcome
        }
    }

    private func markSaveConflict(
        currentSession: DocumentSession,
        loadedFingerprint: FileFingerprint?,
        currentFingerprint: FileFingerprint?
    ) -> DocumentConflict {
        let detectedAt = Date()
        let conflict = DocumentConflict(
            detectedAt: detectedAt,
            loadedFingerprint: loadedFingerprint,
            currentFingerprint: currentFingerprint
        )
        let externalChange = DocumentExternalChange(
            kind: .modified,
            detectedAt: detectedAt,
            url: currentSession.url,
            fileFingerprint: currentFingerprint
        )
        let documentID = currentSession.id
        var conflictedSession = session?.id == documentID
            ? session ?? currentSession
            : sessionStore.session(for: documentID) ?? currentSession
        conflictedSession.isDirty = true
        conflictedSession.saveState = .conflicted
        conflictedSession.conflict = conflict
        conflictedSession.externalChange = externalChange

        if session?.id == documentID {
            session = conflictedSession
        }
        sessionStore.upsertSession(conflictedSession)
        lastSaveResult = .conflicted(documentID: documentID, conflict: conflict)

        return conflict
    }

    private func processPendingFileWatchEventAfterSave(
        for documentID: DocumentSession.ID
    ) async -> (result: DocumentSaveResult, error: (any Error)?)? {
        guard let event = pendingFileWatchEventsAfterSave.removeValue(forKey: documentID) else {
            return nil
        }

        _ = await processExternalFileEvent(event)

        let latestSession = session?.id == documentID
            ? session
            : sessionStore.session(for: documentID)
        guard let latestSession else {
            return nil
        }

        switch latestSession.saveState {
        case .conflicted:
            guard let conflict = latestSession.conflict else {
                return nil
            }
            return (
                DocumentSaveResult.conflicted(documentID: documentID, conflict: conflict),
                DocumentEditorError.conflicted(conflict)
            )
        case .failed:
            if let lastSaveResult, lastSaveResult.documentID == documentID {
                return (lastSaveResult, nil)
            }
            return nil
        case .clean, .dirty, .saving:
            return nil
        }
    }
}

enum DocumentEditorError: LocalizedError, Equatable {
    case sessionNotFound(DocumentSession.ID)
    case missingSession
    case saveAlreadyInProgress
    case conflicted(DocumentConflict)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Document session was not found."
        case .missingSession:
            return "No document session is loaded."
        case .saveAlreadyInProgress:
            return "Document save is already in progress."
        case .conflicted:
            return "Document has external changes on disk."
        }
    }
}

extension DocumentSaveFailure {
    init(documentEditorError: DocumentEditorError) {
        switch documentEditorError {
        case .sessionNotFound:
            self.init(kind: .sessionNotFound, message: documentEditorError.localizedDescription)
        case .missingSession:
            self.init(kind: .missingSession, message: documentEditorError.localizedDescription)
        case .saveAlreadyInProgress:
            self.init(kind: .saveAlreadyInProgress, message: documentEditorError.localizedDescription)
        case .conflicted:
            self.init(kind: .conflicted, message: documentEditorError.localizedDescription)
        }
    }

    init(error: any Error) {
        if let documentEditorError = error as? DocumentEditorError {
            self.init(documentEditorError: documentEditorError)
            return
        }

        self.init(kind: .fileIO, message: error.localizedDescription)
    }
}
