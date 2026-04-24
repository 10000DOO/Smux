import Foundation

struct PreviewState: Identifiable, Codable, Hashable {
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

struct SanitizedMarkdown: Codable, Hashable {
    var html: String
}

struct SourceRange: Codable, Hashable {
    var startLine: Int
    var endLine: Int
}

enum MermaidBlockRenderStatus: String, Codable, Hashable {
    case pending
    case rendering
    case rendered
    case failed
}

enum MermaidRenderArtifact: Codable, Hashable {
    case sanitizedSVG(String)
    case sanitizedHTML(String)
}

struct MermaidBlockState: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceRange: SourceRange
    var status: MermaidBlockRenderStatus
    var artifact: MermaidRenderArtifact?
    var errorMessage: String?
}

struct PreviewRenderError: Identifiable, Codable, Hashable {
    var id: UUID
    var message: String
    var sourceRange: SourceRange?
}
