import Foundation

enum TerminalSessionStatus: String, Codable, Hashable {
    case idle
    case starting
    case running
    case terminated
    case failed
    case restorable
}

struct TerminalSession: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var workspaceID: Workspace.ID
    var workingDirectory: URL
    var processID: Int32?
    var shell: String?
    var command: [String]
    var status: TerminalSessionStatus
    var title: String
    var createdAt: Date
    var lastActivityAt: Date
    var lastOutputSummary: String?
}
