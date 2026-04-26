import Foundation

nonisolated struct WorkspaceSnapshot: Codable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var workspaceID: Workspace.ID
    var rootBookmark: Data?
    var panelTree: PanelNode?
    var workspaceSessions: [WorkspaceSession]
    var sessions: [TerminalSession]
    var documents: [DocumentSession]
    var previews: [PreviewState]
    var leftRailState: LeftRailState
}

nonisolated struct LeftRailState: Codable, Hashable {
    var selectedWorkspaceID: Workspace.ID?
    var selectedPanelID: PanelNode.ID?
    var isFileTreeVisible: Bool
}

extension WorkspaceSnapshot {
    init(
        workspace: Workspace,
        panelTree: PanelNode?,
        workspaceSessions: [WorkspaceSession]? = nil,
        sessions: [TerminalSession] = [],
        documents: [DocumentSession] = [],
        previews: [PreviewState] = [],
        leftRailState: LeftRailState? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.workspaceID = workspace.id
        self.rootBookmark = workspace.securityBookmark
        self.panelTree = panelTree
        self.workspaceSessions = workspaceSessions ?? Self.migratedWorkspaceSessions(
            sessions: sessions,
            documents: documents,
            previews: previews
        )
        self.sessions = sessions
        self.documents = documents
        self.previews = previews
        self.leftRailState = leftRailState ?? .default(
            workspaceID: workspace.id,
            panelID: panelTree?.firstLeafID
        )
    }
}

extension WorkspaceSnapshot {
    nonisolated static func migratedWorkspaceSessions(
        sessions: [TerminalSession],
        documents: [DocumentSession],
        previews: [PreviewState]
    ) -> [WorkspaceSession] {
        sessions.map { WorkspaceSession(terminal: $0, id: $0.id) }
            + documents.map {
                WorkspaceSession(document: $0, id: $0.id, createdAt: Self.migratedSessionTimestamp)
            }
            + previews.compactMap { preview in
                guard let document = documents.first(where: { $0.id == preview.sourceDocumentID }) else {
                    return nil
                }

                return WorkspaceSession(
                    preview: preview,
                    workspaceID: document.workspaceID,
                    id: preview.id,
                    createdAt: Self.migratedSessionTimestamp
                )
            }
    }

    private nonisolated static let migratedSessionTimestamp = Date(timeIntervalSince1970: 0)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaceID
        case rootBookmark
        case panelTree
        case workspaceSessions
        case sessions
        case documents
        case previews
        case leftRailState
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        workspaceID = try container.decode(Workspace.ID.self, forKey: .workspaceID)
        rootBookmark = try container.decodeIfPresent(Data.self, forKey: .rootBookmark)
        panelTree = try container.decodeIfPresent(PanelNode.self, forKey: .panelTree)
        sessions = try container.decodeIfPresent([TerminalSession].self, forKey: .sessions) ?? []
        documents = try container.decodeIfPresent([DocumentSession].self, forKey: .documents) ?? []
        previews = try container.decodeIfPresent([PreviewState].self, forKey: .previews) ?? []
        workspaceSessions = try container.decodeIfPresent(
            [WorkspaceSession].self,
            forKey: .workspaceSessions
        ) ?? Self.migratedWorkspaceSessions(
            sessions: sessions,
            documents: documents,
            previews: previews
        )
        leftRailState = try container.decode(LeftRailState.self, forKey: .leftRailState)
    }
}

extension LeftRailState {
    static func `default`(
        workspaceID: Workspace.ID? = nil,
        panelID: PanelNode.ID? = nil
    ) -> LeftRailState {
        LeftRailState(
            selectedWorkspaceID: workspaceID,
            selectedPanelID: panelID,
            isFileTreeVisible: true
        )
    }
}
