import Foundation

nonisolated enum AgentKind: String, Codable, Hashable {
    case codex
    case claude
    case unknown
}

nonisolated enum AgentExecutionState: String, Codable, Hashable {
    case idle
    case running
    case waitingForInput
    case permissionRequested
    case completed
    case failed
    case terminated
    case unknown
}

nonisolated enum AgentStatusSource: String, Codable, Hashable {
    case terminalOutput
    case hookPayload
    case command
    case unknown
}

nonisolated struct AgentStatus: Identifiable, Codable, Hashable {
    var id: UUID
    var agentKind: AgentKind
    var state: AgentExecutionState
    var confidence: Double
    var source: AgentStatusSource
    var message: String?
    var updatedAt: Date
}
