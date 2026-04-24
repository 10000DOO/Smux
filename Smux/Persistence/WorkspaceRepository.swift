import Foundation

protocol WorkspaceRepository {
    func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot?
    func saveSnapshot(_ snapshot: WorkspaceSnapshot) async throws
}

struct NoopWorkspaceRepository: WorkspaceRepository {
    func loadSnapshot(for rootURL: URL) async throws -> WorkspaceSnapshot? {
        nil
    }

    func saveSnapshot(_ snapshot: WorkspaceSnapshot) async throws {}
}
