import Foundation

nonisolated protocol WorkspaceRepository {
    func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot?
    func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws
}

nonisolated struct NoopWorkspaceRepository: WorkspaceRepository {
    func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
        nil
    }

    func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws {}
}

nonisolated final class FileBackedWorkspaceRepository: WorkspaceRepository {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileBackedWorkspaceRepository.defaultBaseDirectory,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
        let fileURL = snapshotURL(for: rootURL)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: WorkspaceSnapshot, for rootURL: URL) async throws {
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL(for: rootURL), options: .atomic)
    }

    private static var defaultBaseDirectory: URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return applicationSupportDirectory
            .appendingPathComponent("Smux", isDirectory: true)
            .appendingPathComponent("Workspaces", isDirectory: true)
    }

    private func snapshotURL(for rootURL: URL) -> URL {
        baseDirectory.appendingPathComponent(snapshotFileName(for: rootURL), isDirectory: false)
    }

    private func snapshotFileName(for rootURL: URL) -> String {
        let canonicalURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let displayName = sanitizedFileNameComponent(
            canonicalURL.lastPathComponent.isEmpty ? "workspace" : canonicalURL.lastPathComponent
        )
        let hash = stableHash(for: canonicalURL.path)

        return "\(displayName)-\(hash).json"
    }

    private func sanitizedFileNameComponent(_ value: String) -> String {
        let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let sanitized = String(value.map { allowedCharacters.contains($0) ? $0 : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return sanitized.isEmpty ? "workspace" : sanitized
    }

    private func stableHash(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }

        return String(hash, radix: 16)
    }
}
