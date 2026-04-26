import Foundation

nonisolated enum MermaidRenderError: Error, Equatable, LocalizedError {
    case emptySource
    case unsupportedSyntax(String)
    case missingOfficialMermaidBundle([String])
    case officialRendererUnavailable

    var errorDescription: String? {
        switch self {
        case .emptySource:
            return "Mermaid source is empty."
        case .unsupportedSyntax(let firstLine):
            return "Unsupported Mermaid diagram declaration: \(firstLine)"
        case .missingOfficialMermaidBundle(let fileNames):
            let candidates = fileNames.joined(separator: " or ")
            return "Official Mermaid JavaScript bundle is missing. Add \(candidates) to the app target resources for offline rendering."
        case .officialRendererUnavailable:
            return "Offline Mermaid JavaScript execution is not wired yet."
        }
    }
}

nonisolated struct MermaidJavaScriptResource: Equatable {
    var fileName: String
    var source: String
}

nonisolated struct MermaidRenderRequest: Equatable {
    var blockID: UUID
    var sourceRange: SourceRange
    var source: String
    var diagramType: String
    var javaScriptResource: MermaidJavaScriptResource
}

nonisolated protocol MermaidJavaScriptResourceProviding {
    func loadMermaidJavaScriptResource() throws -> MermaidJavaScriptResource
}

nonisolated protocol MermaidDiagramRendering {
    func render(_ request: MermaidRenderRequest) async throws -> MermaidRenderArtifact
}

nonisolated struct BundledMermaidJavaScriptResourceProvider: MermaidJavaScriptResourceProviding {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadMermaidJavaScriptResource() throws -> MermaidJavaScriptResource {
        for candidate in Self.officialBundleCandidates {
            guard let url = bundle.url(forResource: candidate.resourceName, withExtension: candidate.fileExtension) else {
                continue
            }

            return MermaidJavaScriptResource(
                fileName: candidate.fileName,
                source: try String(contentsOf: url, encoding: .utf8)
            )
        }

        throw MermaidRenderError.missingOfficialMermaidBundle(
            Self.officialBundleCandidates.map(\.fileName)
        )
    }

    private static let officialBundleCandidates = [
        MermaidResourceCandidate(resourceName: "mermaid.min", fileExtension: "js"),
        MermaidResourceCandidate(resourceName: "mermaid", fileExtension: "js")
    ]
}

nonisolated struct UnavailableMermaidDiagramRenderer: MermaidDiagramRendering {
    func render(_ request: MermaidRenderRequest) async throws -> MermaidRenderArtifact {
        throw MermaidRenderError.officialRendererUnavailable
    }
}

nonisolated final class MermaidRenderCoordinator {
    private let resourceProvider: MermaidJavaScriptResourceProviding
    private let renderer: MermaidDiagramRendering

    init(
        resourceProvider: MermaidJavaScriptResourceProviding = BundledMermaidJavaScriptResourceProvider(),
        renderer: MermaidDiagramRendering = UnavailableMermaidDiagramRenderer()
    ) {
        self.resourceProvider = resourceProvider
        self.renderer = renderer
    }

    func render(block: MermaidBlockState) async throws -> MermaidRenderArtifact {
        try Task.checkCancellation()

        let prepared = try prepare(block: block)
        let resource = try resourceProvider.loadMermaidJavaScriptResource()
        try Task.checkCancellation()

        let request = MermaidRenderRequest(
            blockID: block.id,
            sourceRange: block.sourceRange,
            source: prepared.source,
            diagramType: prepared.diagramType,
            javaScriptResource: resource
        )

        let artifact = try await renderer.render(request)
        try Task.checkCancellation()
        return artifact
    }

    func fallbackArtifact(for block: MermaidBlockState) throws -> MermaidRenderArtifact {
        let prepared = try prepare(block: block)
        let escapedSource = escapeHTML(prepared.source)

        return .sanitizedHTML(
            """
            <pre class="mermaid-fallback-source" data-renderer="fallback" data-diagram-type="\(prepared.diagramType)" aria-label="Mermaid fallback source"><code>\(escapedSource)</code></pre>
            """
        )
    }

    func cancelAll() {}

    private func prepare(block: MermaidBlockState) throws -> PreparedMermaidDiagram {
        let source = normalize(block.source)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MermaidRenderError.emptySource
        }

        let firstLine = try firstDiagramLine(in: source)
        let diagramType = try diagramType(from: firstLine)
        return PreparedMermaidDiagram(source: source, diagramType: diagramType)
    }

    private func normalize(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func firstDiagramLine(in source: String) throws -> String {
        let line = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { line in
                !line.isEmpty && !line.hasPrefix("%%")
            }

        guard let line else {
            throw MermaidRenderError.emptySource
        }

        return line
    }

    private func diagramType(from firstLine: String) throws -> String {
        let candidates = [
            "architecture-beta",
            "block",
            "classDiagram",
            "erDiagram",
            "flowchart",
            "gantt",
            "gitGraph",
            "graph",
            "journey",
            "kanban",
            "mindmap",
            "packet-beta",
            "pie",
            "quadrantChart",
            "requirementDiagram",
            "sankey-beta",
            "sequenceDiagram",
            "stateDiagram-v2",
            "stateDiagram",
            "timeline",
            "xyChart-beta"
        ]

        guard let diagramType = candidates.first(where: { candidate in
            firstLine == candidate || firstLine.hasPrefix("\(candidate) ")
        }) else {
            throw MermaidRenderError.unsupportedSyntax(firstLine)
        }

        return diagramType
    }

    private func escapeHTML(_ source: String) -> String {
        source.reduce(into: "") { escaped, character in
            switch character {
            case "&":
                escaped += "&amp;"
            case "<":
                escaped += "&lt;"
            case ">":
                escaped += "&gt;"
            case "\"":
                escaped += "&quot;"
            case "'":
                escaped += "&#39;"
            default:
                escaped.append(character)
            }
        }
    }
}

private nonisolated struct MermaidResourceCandidate {
    var resourceName: String
    var fileExtension: String

    var fileName: String {
        "\(resourceName).\(fileExtension)"
    }
}

private nonisolated struct PreparedMermaidDiagram {
    var source: String
    var diagramType: String
}
