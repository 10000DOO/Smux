import Foundation

nonisolated protocol RecentWorkspaceRepository {
    func loadRecentWorkspaces() throws -> [RecentWorkspace]
    func saveRecentWorkspaces(_ recentWorkspaces: [RecentWorkspace]) throws
}

nonisolated struct NoopRecentWorkspaceRepository: RecentWorkspaceRepository {
    func loadRecentWorkspaces() throws -> [RecentWorkspace] {
        []
    }

    func saveRecentWorkspaces(_ recentWorkspaces: [RecentWorkspace]) throws {}
}

nonisolated final class FileBackedRecentWorkspaceRepository: RecentWorkspaceRepository {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = FileBackedRecentWorkspaceRepository.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadRecentWorkspaces() throws -> [RecentWorkspace] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([RecentWorkspace].self, from: data)
    }

    func saveRecentWorkspaces(_ recentWorkspaces: [RecentWorkspace]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try JSONEncoder().encode(recentWorkspaces)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return applicationSupportDirectory
            .appendingPathComponent("Smux", isDirectory: true)
            .appendingPathComponent("RecentWorkspaces.json", isDirectory: false)
    }
}
