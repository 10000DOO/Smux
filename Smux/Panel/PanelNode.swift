import Foundation

nonisolated enum PanelNodeKind: String, Codable, Hashable {
    case leaf
    case split
}

nonisolated enum SplitDirection: String, Codable, Hashable {
    case horizontal
    case vertical
}

nonisolated enum PanelSurfaceDescriptor: Codable, Hashable {
    case terminal(sessionID: TerminalSession.ID)
    case editor(documentID: DocumentSession.ID)
    case preview(previewID: PreviewState.ID)
    case empty
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
    static let placeholder = leaf(surface: .empty)

    static func leaf(id: ID = UUID(), surface: PanelSurfaceDescriptor = .empty) -> PanelNode {
        PanelNode(id: id, kind: .leaf, surface: surface)
    }

    static func split(
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

    var isLeaf: Bool {
        kind == .leaf
    }

    var isSplit: Bool {
        kind == .split
    }

    var normalizedRatio: Double {
        Self.clampedRatio(ratio ?? 0.5)
    }

    static func clampedRatio(_ ratio: Double) -> Double {
        min(max(ratio, 0.1), 0.9)
    }

    var firstLeafID: ID? {
        if isLeaf {
            return id
        }

        return children.lazy.compactMap(\.firstLeafID).first
    }

    var leafIDs: [ID] {
        if isLeaf {
            return [id]
        }

        return children.flatMap(\.leafIDs)
    }

    func contains(panelID: ID) -> Bool {
        if id == panelID {
            return true
        }

        return children.contains { $0.contains(panelID: panelID) }
    }

    func containsLeaf(panelID: ID) -> Bool {
        if id == panelID {
            return isLeaf
        }

        return children.contains { $0.containsLeaf(panelID: panelID) }
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
}
