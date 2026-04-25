import Foundation

nonisolated struct LoadedDocument: Hashable, Sendable {
    var text: String
    var fingerprint: FileFingerprint
}

nonisolated protocol DocumentFileIO: Sendable {
    func loadText(from url: URL) async throws -> LoadedDocument
    func saveText(_ text: String, to url: URL) async throws -> FileFingerprint
    func fingerprint(for url: URL) async throws -> FileFingerprint
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

    func saveText(_ text: String, to url: URL) async throws -> FileFingerprint {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)

        return try fingerprint(for: url, data: data)
    }

    func fingerprint(for url: URL) async throws -> FileFingerprint {
        let data = try Data(contentsOf: url)
        return try fingerprint(for: url, data: data)
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
