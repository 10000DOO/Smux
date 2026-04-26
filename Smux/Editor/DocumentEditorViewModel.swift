import Combine
import Foundation

@MainActor
final class DocumentEditorViewModel: ObservableObject {
    @Published var session: DocumentSession?
    @Published var text = ""
    @Published var selectedRange: NSRange?
    @Published private(set) var lastSaveResult: DocumentSaveResult?

    private let sessionStore: any DocumentSessionStoring
    private let fileIO: any DocumentFileIO
    private var savingSessionIDs: Set<DocumentSession.ID> = []

    init(
        sessionStore: any DocumentSessionStoring = DocumentSessionStore(),
        fileIO: any DocumentFileIO = FileBackedDocumentFileIO()
    ) {
        self.sessionStore = sessionStore
        self.fileIO = fileIO
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

        text = loadedDocument.text
        selectedRange = NSRange(location: 0, length: 0)
        lastSaveResult = nil
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
        currentSession.saveState = .dirty
        currentSession.conflict = nil

        lastSaveResult = nil
        session = currentSession
        sessionStore.upsertSession(currentSession)
    }

    func updateSelectedRange(_ selectedRange: NSRange?) {
        self.selectedRange = selectedRange
    }

    func saveNow() async throws {
        let outcome = await saveCurrentSession()
        lastSaveResult = outcome.result

        if let error = outcome.error {
            throw error
        }
    }

    func saveNowResult() async -> DocumentSaveResult {
        let outcome = await saveCurrentSession()
        lastSaveResult = outcome.result

        return outcome.result
    }

    private func saveCurrentSession() async -> (result: DocumentSaveResult, error: (any Error)?) {
        guard var currentSession = session else {
            return (
                DocumentSaveResult.failed(
                    documentID: nil,
                    failure: DocumentSaveFailure(documentEditorError: .missingSession)
                ),
                DocumentEditorError.missingSession
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
        defer {
            savingSessionIDs.remove(currentSession.id)
        }

        let saveText = text
        let savedTextVersion = currentSession.textVersion
        let loadedFingerprint = currentSession.fileFingerprint

        currentSession.saveState = .saving
        session = currentSession
        sessionStore.upsertSession(currentSession)

        do {
            let diskFingerprint = try await fileIO.fingerprint(for: currentSession.url)
            guard loadedFingerprint == diskFingerprint else {
                let conflict = DocumentConflict(
                    detectedAt: Date(),
                    loadedFingerprint: loadedFingerprint,
                    currentFingerprint: diskFingerprint
                )
                currentSession.isDirty = true
                currentSession.saveState = .conflicted
                currentSession.conflict = conflict

                session = currentSession
                sessionStore.upsertSession(currentSession)
                let error = DocumentEditorError.conflicted(conflict)

                return (
                    DocumentSaveResult.conflicted(documentID: currentSession.id, conflict: conflict),
                    error
                )
            }

            let fingerprint = try await fileIO.saveText(saveText, to: currentSession.url)
            var latestSession = session?.id == currentSession.id
                ? session ?? currentSession
                : sessionStore.session(for: currentSession.id) ?? currentSession
            latestSession.fileFingerprint = fingerprint
            latestSession.conflict = nil

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

            if latestSession.saveState == .clean {
                return (DocumentSaveResult.saved(documentID: currentSession.id), nil)
            }

            return (DocumentSaveResult.dirty(documentID: currentSession.id), nil)
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

            return (
                DocumentSaveResult.failed(
                    documentID: currentSession.id,
                    failure: DocumentSaveFailure(error: error)
                ),
                error
            )
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
