import Foundation

nonisolated struct PreviewState: Identifiable, Codable, Hashable {
    typealias ID = UUID
    static let defaultZoom = 1.0
    static let minimumZoom = 0.5
    static let maximumZoom = 3.0
    static let zoomStep = 0.1

    var id: ID
    var sourceDocumentID: DocumentSession.ID
    var renderVersion: Int
    var sanitizedMarkdown: SanitizedMarkdown?
    var mermaidBlocks: [MermaidBlockState]
    var errors: [PreviewRenderError]
    var zoom: Double
    var scrollAnchor: String?

    static func clampedZoom(_ zoom: Double) -> Double {
        min(max(zoom.isFinite ? zoom : defaultZoom, minimumZoom), maximumZoom)
    }
}

nonisolated struct SanitizedMarkdown: Codable, Hashable {
    var html: String
}

nonisolated struct SourceRange: Codable, Hashable {
    var startLine: Int
    var endLine: Int
}

nonisolated enum MermaidBlockRenderStatus: String, Codable, Hashable {
    case pending
    case rendering
    case rendered
    case failed
}

nonisolated enum MermaidRenderArtifact: Codable, Hashable {
    case sanitizedSVG(String)
    case sanitizedHTML(String)
}

nonisolated struct MermaidBlockState: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceRange: SourceRange
    var source: String
    var status: MermaidBlockRenderStatus
    var artifact: MermaidRenderArtifact?
    var errorMessage: String?

    init(
        id: UUID,
        sourceRange: SourceRange,
        source: String = "",
        status: MermaidBlockRenderStatus,
        artifact: MermaidRenderArtifact?,
        errorMessage: String?
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.source = source
        self.status = status
        self.artifact = artifact
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceRange
        case source
        case status
        case artifact
        case errorMessage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceRange = try container.decode(SourceRange.self, forKey: .sourceRange)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        status = try container.decode(MermaidBlockRenderStatus.self, forKey: .status)
        artifact = try container.decodeIfPresent(MermaidRenderArtifact.self, forKey: .artifact)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

nonisolated struct PreviewRenderError: Identifiable, Codable, Hashable {
    var id: UUID
    var message: String
    var sourceRange: SourceRange?
}
