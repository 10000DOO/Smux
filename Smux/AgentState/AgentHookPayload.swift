import Foundation

nonisolated struct AgentHookPayload: Codable, Hashable {
    var agentKind: AgentKind
    var eventName: String
    var title: String?
    var body: String?
    var message: String?
    var occurredAt: Date?

    init(
        agentKind: AgentKind = .unknown,
        eventName: String,
        title: String? = nil,
        body: String? = nil,
        message: String? = nil,
        occurredAt: Date? = nil
    ) {
        self.agentKind = agentKind
        self.eventName = eventName
        self.title = title
        self.body = body
        self.message = message
        self.occurredAt = occurredAt
    }
}
