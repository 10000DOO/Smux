import Foundation

nonisolated enum PanelNodeKind: String, Codable, Hashable {
    case leaf
    case split
}

nonisolated enum SplitDirection: String, Codable, Hashable {
    case horizontal
    case vertical
}

nonisolated enum PanelViewportDescriptor: Codable, Hashable {
    case session(sessionID: WorkspaceSession.ID)
    case empty
}

typealias PanelSurfaceDescriptor = PanelViewportDescriptor

extension PanelViewportDescriptor {
    nonisolated var sessionID: WorkspaceSession.ID? {
        switch self {
        case .session(let sessionID):
            return sessionID
        case .empty:
            return nil
        }
    }
}

extension PanelViewportDescriptor {
    private enum CodingKeys: String, CodingKey {
        case session
        case terminal
        case editor
        case preview
        case empty
    }

    private enum SessionCodingKeys: String, CodingKey {
        case sessionID
        case documentID
        case previewID
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.empty) {
            self = .empty
            return
        }

        if let sessionID = try Self.decodeSessionID(
            from: container,
            caseKey: .session,
            idKey: .sessionID
        ) {
            self = .session(sessionID: sessionID)
            return
        }

        if let terminalID = try Self.decodeSessionID(
            from: container,
            caseKey: .terminal,
            idKey: .sessionID
        ) {
            self = .session(sessionID: terminalID)
            return
        }

        if let documentID = try Self.decodeSessionID(
            from: container,
            caseKey: .editor,
            idKey: .documentID
        ) {
            self = .session(sessionID: documentID)
            return
        }

        if let previewID = try Self.decodeSessionID(
            from: container,
            caseKey: .preview,
            idKey: .previewID
        ) {
            self = .session(sessionID: previewID)
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported panel surface descriptor."
            )
        )
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .session(let sessionID):
            var sessionContainer = container.nestedContainer(
                keyedBy: SessionCodingKeys.self,
                forKey: .session
            )
            try sessionContainer.encode(sessionID, forKey: .sessionID)
        case .empty:
            _ = container.nestedContainer(keyedBy: SessionCodingKeys.self, forKey: .empty)
        }
    }

    private nonisolated static func decodeSessionID(
        from container: KeyedDecodingContainer<CodingKeys>,
        caseKey: CodingKeys,
        idKey: SessionCodingKeys
    ) throws -> WorkspaceSession.ID? {
        guard container.contains(caseKey) else {
            return nil
        }

        let nestedContainer = try container.nestedContainer(keyedBy: SessionCodingKeys.self, forKey: caseKey)
        return try nestedContainer.decode(WorkspaceSession.ID.self, forKey: idKey)
    }
}

nonisolated struct PanelNode: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var kind: PanelNodeKind
    var direction: SplitDirection?
    var ratio: Double?
    var children: [PanelNode]
    var surface: PanelSurfaceDescriptor?

    init(
        id: ID = UUID(),
        kind: PanelNodeKind,
        direction: SplitDirection? = nil,
        ratio: Double? = nil,
        children: [PanelNode] = [],
        surface: PanelSurfaceDescriptor? = nil
    ) {
        self.id = id
        self.kind = kind

        switch kind {
        case .leaf:
            self.direction = nil
            self.ratio = nil
            self.children = []
            self.surface = surface ?? .empty
        case .split:
            self.direction = direction
            self.ratio = ratio
            self.children = Array(children.prefix(2))
            self.surface = nil
        }
    }
}

extension PanelNode {
    nonisolated static let placeholder = leaf(surface: .empty)

    nonisolated static func leaf(id: ID = UUID(), surface: PanelSurfaceDescriptor = .empty) -> PanelNode {
        PanelNode(id: id, kind: .leaf, surface: surface)
    }

    nonisolated static func split(
        id: ID = UUID(),
        direction: SplitDirection,
        ratio: Double = 0.5,
        first: PanelNode,
        second: PanelNode
    ) -> PanelNode {
        PanelNode(
            id: id,
            kind: .split,
            direction: direction,
            ratio: ratio,
            children: [first, second]
        )
    }

    nonisolated var isLeaf: Bool {
        kind == .leaf
    }

    nonisolated var isSplit: Bool {
        kind == .split
    }

    nonisolated var normalizedRatio: Double {
        Self.clampedRatio(ratio ?? 0.5)
    }

    nonisolated static func clampedRatio(_ ratio: Double) -> Double {
        min(max(ratio, 0.1), 0.9)
    }

    nonisolated var firstLeafID: ID? {
        if isLeaf {
            return id
        }

        return children.lazy.compactMap(\.firstLeafID).first
    }

    nonisolated var lastLeafID: ID? {
        if isLeaf {
            return id
        }

        return children.reversed().lazy.compactMap(\.lastLeafID).first
    }

    nonisolated var leafIDs: [ID] {
        if isLeaf {
            return [id]
        }

        return children.flatMap(\.leafIDs)
    }

    nonisolated var workspaceSessionIDs: [WorkspaceSession.ID] {
        if isLeaf {
            return surface?.sessionID.map { [$0] } ?? []
        }

        return children.flatMap(\.workspaceSessionIDs)
    }

    func contains(panelID: ID) -> Bool {
        if id == panelID {
            return true
        }

        return children.contains { $0.contains(panelID: panelID) }
    }

    nonisolated func containsLeaf(panelID: ID) -> Bool {
        if id == panelID {
            return isLeaf
        }

        return children.contains { $0.containsLeaf(panelID: panelID) }
    }

    func surface(forLeaf panelID: ID?) -> PanelSurfaceDescriptor? {
        guard let panelID else {
            return nil
        }

        if id == panelID, isLeaf {
            return surface
        }

        return children.lazy.compactMap { $0.surface(forLeaf: panelID) }.first
    }

    nonisolated func panelID(containingWorkspaceSession sessionID: WorkspaceSession.ID) -> ID? {
        if surface?.sessionID == sessionID, isLeaf {
            return id
        }

        return children.lazy.compactMap {
            $0.panelID(containingWorkspaceSession: sessionID)
        }.first
    }

    func replacingSurface(panelID: ID, with surface: PanelSurfaceDescriptor) -> PanelNode {
        guard id != panelID || isLeaf else {
            return self
        }

        guard id != panelID else {
            return .leaf(id: id, surface: surface)
        }

        guard isSplit else {
            return self
        }

        return PanelNode(
            id: id,
            kind: .split,
            direction: direction,
            ratio: ratio,
            children: children.map { $0.replacingSurface(panelID: panelID, with: surface) }
        )
    }

    func updatingSplitRatio(splitID: ID, ratio: Double) -> PanelNode? {
        if id == splitID, isSplit {
            return PanelNode(
                id: id,
                kind: .split,
                direction: direction,
                ratio: Self.clampedRatio(ratio),
                children: children
            )
        }

        guard isSplit else {
            return nil
        }

        for childIndex in children.indices {
            guard let updatedChild = children[childIndex].updatingSplitRatio(
                splitID: splitID,
                ratio: ratio
            ) else {
                continue
            }

            var updatedChildren = children
            updatedChildren[childIndex] = updatedChild

            return PanelNode(
                id: id,
                kind: .split,
                direction: direction,
                ratio: self.ratio,
                children: updatedChildren
            )
        }

        return nil
    }

    func removingLeaf(panelID: ID) -> (node: PanelNode, focusCandidateID: ID?)? {
        guard isSplit, children.count == 2 else {
            return nil
        }

        if children[0].containsLeaf(panelID: panelID) {
            return removingLeaf(
                panelID: panelID,
                removedChildIndex: 0,
                siblingIndex: 1
            )
        }

        if children[1].containsLeaf(panelID: panelID) {
            return removingLeaf(
                panelID: panelID,
                removedChildIndex: 1,
                siblingIndex: 0
            )
        }

        return nil
    }

    func splittingLeaf(
        panelID: ID,
        direction: SplitDirection,
        newSurface: PanelSurfaceDescriptor
    ) -> (node: PanelNode, newPanelID: ID)? {
        if id == panelID, isLeaf {
            let newPanelID = ID()
            let splitNode = PanelNode.split(
                direction: direction,
                first: self,
                second: .leaf(id: newPanelID, surface: newSurface)
            )

            return (splitNode, newPanelID)
        }

        guard isSplit else {
            return nil
        }

        for childIndex in children.indices {
            guard let result = children[childIndex].splittingLeaf(
                panelID: panelID,
                direction: direction,
                newSurface: newSurface
            ) else {
                continue
            }

            var updatedChildren = children
            updatedChildren[childIndex] = result.node

            return (
                PanelNode(
                    id: id,
                    kind: .split,
                    direction: self.direction,
                    ratio: ratio,
                    children: updatedChildren
                ),
                result.newPanelID
            )
        }

        return nil
    }

    private func removingLeaf(
        panelID: ID,
        removedChildIndex: Int,
        siblingIndex: Int
    ) -> (node: PanelNode, focusCandidateID: ID?)? {
        let child = children[removedChildIndex]
        let sibling = children[siblingIndex]

        if child.isLeaf, child.id == panelID {
            let focusCandidateID = siblingIndex < removedChildIndex
                ? sibling.lastLeafID
                : sibling.firstLeafID
            return (sibling, focusCandidateID)
        }

        guard let removal = child.removingLeaf(panelID: panelID) else {
            return nil
        }

        var updatedChildren = children
        updatedChildren[removedChildIndex] = removal.node

        return (
            PanelNode(
                id: id,
                kind: .split,
                direction: direction,
                ratio: ratio,
                children: updatedChildren
            ),
            removal.focusCandidateID
        )
    }
}
