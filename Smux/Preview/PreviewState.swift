import Foundation

nonisolated struct PreviewState: Identifiable, Codable, Hashable {
    typealias ID = UUID

    var id: ID
    var sourceDocumentID: DocumentSession.ID
    var renderVersion: Int
    var sanitizedMarkdown: SanitizedMarkdown?
    var mermaidBlocks: [MermaidBlockState]
    var errors: [PreviewRenderError]
    var zoom: Double
    var scrollAnchor: String?
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
    var status: MermaidBlockRenderStatus
    var artifact: MermaidRenderArtifact?
    var errorMessage: String?
}

nonisolated struct PreviewRenderError: Identifiable, Codable, Hashable {
    var id: UUID
    var message: String
    var sourceRange: SourceRange?
}
