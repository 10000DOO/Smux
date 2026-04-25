import Foundation

nonisolated final class AgentStatusDetector {
    private let stateQueue = DispatchQueue(label: "Smux.AgentStatusDetector.state")
    private var sessionKinds: [TerminalSession.ID: AgentKind] = [:]

    func detectStatus(from output: String, sessionID: TerminalSession.ID) -> AgentStatus? {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            return nil
        }

        let explicitKind = Self.detectAgentKind(in: trimmedOutput)
        let agentKind = resolvedAgentKind(explicitKind, sessionID: sessionID)

        guard let match = Self.detectExecutionState(in: trimmedOutput, agentKind: agentKind) else {
            return nil
        }

        return AgentStatus(
            id: UUID(),
            agentKind: agentKind,
            state: match.state,
            confidence: match.confidence,
            source: .terminalOutput,
            message: Self.statusMessage(from: trimmedOutput, fallback: match.message),
            updatedAt: Date()
        )
    }

    func reset(sessionID: TerminalSession.ID) {
        _ = stateQueue.sync {
            sessionKinds.removeValue(forKey: sessionID)
        }
    }

    private func resolvedAgentKind(_ explicitKind: AgentKind, sessionID: TerminalSession.ID) -> AgentKind {
        stateQueue.sync {
            if explicitKind != .unknown {
                sessionKinds[sessionID] = explicitKind
                return explicitKind
            }

            return sessionKinds[sessionID] ?? .unknown
        }
    }

    private static func detectAgentKind(in output: String) -> AgentKind {
        let normalized = output.lowercased()

        if normalized.contains("claude") || normalized.contains("anthropic") {
            return .claude
        }

        if normalized.contains("codex") {
            return .codex
        }

        return .unknown
    }

    private static func detectExecutionState(
        in output: String,
        agentKind: AgentKind
    ) -> AgentStatusMatch? {
        let normalized = output.lowercased()

        for pattern in statusPatterns {
            guard !pattern.requiresKnownAgent || agentKind != .unknown else {
                continue
            }

            if pattern.phrases.contains(where: { normalized.contains($0) }) {
                return AgentStatusMatch(
                    state: pattern.state,
                    confidence: pattern.confidence,
                    message: pattern.message
                )
            }
        }

        return nil
    }

    private static func statusMessage(from output: String, fallback: String) -> String {
        let line = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }

        guard let line else {
            return fallback
        }

        if line.count <= 160 {
            return line
        }

        return String(line.prefix(157)) + "..."
    }

    private static let statusPatterns: [AgentStatusPattern] = [
        AgentStatusPattern(
            state: .permissionRequested,
            phrases: [
                "approval required",
                "requires approval",
                "permission requested",
                "requires your permission",
                "do you want to allow",
                "allow command",
                "approve command",
                "sandbox_permissions",
                "requesting permission"
            ],
            confidence: 0.95,
            message: "Permission requested",
            requiresKnownAgent: true
        ),
        AgentStatusPattern(
            state: .waitingForInput,
            phrases: [
                "waiting for input",
                "user input required",
                "please respond",
                "select an option",
                "choose an option"
            ],
            confidence: 0.9,
            message: "Waiting for input",
            requiresKnownAgent: true
        ),
        AgentStatusPattern(
            state: .failed,
            phrases: [
                "codex failed",
                "claude failed",
                "agent failed",
                "failed with exit code",
                "exited with error",
                "uncaught error"
            ],
            confidence: 0.85,
            message: "Agent failed",
            requiresKnownAgent: true
        ),
        AgentStatusPattern(
            state: .completed,
            phrases: [
                "codex completed",
                "claude completed",
                "task complete",
                "completed successfully",
                "finished successfully",
                "done."
            ],
            confidence: 0.82,
            message: "Agent completed",
            requiresKnownAgent: true
        ),
        AgentStatusPattern(
            state: .terminated,
            phrases: [
                "session terminated",
                "process terminated",
                "agent terminated",
                "cancelled by user",
                "interrupted by user"
            ],
            confidence: 0.82,
            message: "Agent terminated",
            requiresKnownAgent: true
        ),
        AgentStatusPattern(
            state: .running,
            phrases: [
                "codex is working",
                "claude is working",
                "thinking",
                "working",
                "running",
                "processing"
            ],
            confidence: 0.7,
            message: "Agent running",
            requiresKnownAgent: true
        )
    ]
}

private nonisolated struct AgentStatusPattern {
    var state: AgentExecutionState
    var phrases: [String]
    var confidence: Double
    var message: String
    var requiresKnownAgent: Bool
}

private nonisolated struct AgentStatusMatch {
    var state: AgentExecutionState
    var confidence: Double
    var message: String
}
