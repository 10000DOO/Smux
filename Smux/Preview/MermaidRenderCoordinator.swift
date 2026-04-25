import Foundation

nonisolated enum MermaidRenderError: Error, Equatable, LocalizedError {
    case emptySource
    case unsupportedSyntax(String)

    var errorDescription: String? {
        switch self {
        case .emptySource:
            return "Mermaid source is empty."
        case .unsupportedSyntax(let firstLine):
            return "Unsupported Mermaid diagram declaration: \(firstLine)"
        }
    }
}

nonisolated final class MermaidRenderCoordinator {
    func render(block: MermaidBlockState) async throws -> MermaidRenderArtifact {
        try Task.checkCancellation()

        let source = normalize(block.source)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MermaidRenderError.emptySource
        }

        let firstLine = try firstDiagramLine(in: source)
        let diagramType = try diagramType(from: firstLine)
        let escapedSource = escapeHTML(source)

        // Offline-safe placeholder until the bundled Mermaid/WebKit renderer is wired.
        return .sanitizedHTML(
            """
            <pre class="mermaid-placeholder" data-diagram-type="\(diagramType)"><code>\(escapedSource)</code></pre>
            """
        )
    }

    func cancelAll() {}

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
