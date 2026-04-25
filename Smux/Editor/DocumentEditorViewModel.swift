import Combine
import Foundation

@MainActor
final class DocumentEditorViewModel: ObservableObject {
    @Published var session: DocumentSession?
    @Published var text = ""
    @Published var selectedRange: NSRange?

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

        session = currentSession
        sessionStore.upsertSession(currentSession)
    }

    func updateSelectedRange(_ selectedRange: NSRange?) {
        self.selectedRange = selectedRange
    }

    func saveNow() async throws {
        guard var currentSession = session else {
            throw DocumentEditorError.missingSession
        }

        guard !savingSessionIDs.contains(currentSession.id) else {
            throw DocumentEditorError.saveAlreadyInProgress
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
                throw DocumentEditorError.conflicted(conflict)
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
        } catch {
            if case DocumentEditorError.conflicted = error {
                throw error
            }

            var failedSession = session?.id == currentSession.id
                ? session ?? currentSession
                : sessionStore.session(for: currentSession.id) ?? currentSession
            failedSession.isDirty = true
            failedSession.saveState = .failed

            if session?.id == currentSession.id {
                session = failedSession
            }
            sessionStore.upsertSession(failedSession)
            throw error
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
