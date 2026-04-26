import Foundation

nonisolated struct LoadedDocument: Hashable, Sendable {
    var text: String
    var fingerprint: FileFingerprint
}

nonisolated protocol DocumentFileIO: Sendable {
    func loadText(from url: URL) async throws -> LoadedDocument
    func saveText(
        _ text: String,
        to url: URL,
        replacing expectedFingerprint: FileFingerprint?
    ) async throws -> FileFingerprint
    func fingerprint(for url: URL) async throws -> FileFingerprint
    func fileExists(at url: URL) -> Bool
}

nonisolated struct DocumentFileWriteConflict: LocalizedError, Equatable, Sendable {
    var loadedFingerprint: FileFingerprint?
    var currentFingerprint: FileFingerprint?

    var errorDescription: String? {
        "Document changed on disk before it could be saved."
    }
}

nonisolated final class FileBackedDocumentFileIO: DocumentFileIO, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadText(from url: URL) async throws -> LoadedDocument {
        let data = try Data(contentsOf: url)

        return LoadedDocument(
            text: String(decoding: data, as: UTF8.self),
            fingerprint: try fingerprint(for: url, data: data)
        )
    }

    func saveText(
        _ text: String,
        to url: URL,
        replacing expectedFingerprint: FileFingerprint?
    ) async throws -> FileFingerprint {
        let data = Data(text.utf8)
        var coordinationError: NSError?
        var writeResult: Result<FileFingerprint, any Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try verifyExpectedFingerprint(expectedFingerprint, at: coordinatedURL)
                try data.write(to: coordinatedURL, options: .atomic)
                writeResult = .success(try fingerprint(for: coordinatedURL, data: data))
            } catch {
                writeResult = .failure(error)
            }
        }

        if let writeResult {
            return try writeResult.get()
        }

        if let coordinationError {
            throw coordinationError
        }

        throw CocoaError(.fileWriteUnknown)
    }

    func fingerprint(for url: URL) async throws -> FileFingerprint {
        let data = try Data(contentsOf: url)
        return try fingerprint(for: url, data: data)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func verifyExpectedFingerprint(
        _ expectedFingerprint: FileFingerprint?,
        at url: URL
    ) throws {
        guard let expectedFingerprint else {
            return
        }

        let currentFingerprint: FileFingerprint?
        do {
            let currentData = try Data(contentsOf: url)
            currentFingerprint = try fingerprint(for: url, data: currentData)
        } catch {
            guard !fileExists(at: url) else {
                throw error
            }
            throw DocumentFileWriteConflict(
                loadedFingerprint: expectedFingerprint,
                currentFingerprint: nil
            )
        }

        guard currentFingerprint == expectedFingerprint else {
            throw DocumentFileWriteConflict(
                loadedFingerprint: expectedFingerprint,
                currentFingerprint: currentFingerprint
            )
        }
    }

    private func fingerprint(for url: URL, data: Data) throws -> FileFingerprint {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let modificationDate = attributes[.modificationDate] as? Date
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? Int64(data.count)

        return FileFingerprint(
            modificationDate: modificationDate,
            size: size,
            contentHash: stableHash(for: data)
        )
    }

    private func stableHash(for data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }

        return String(hash, radix: 16)
    }
}
