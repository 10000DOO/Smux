import Foundation

nonisolated final class MarkdownPreviewPipeline {
    private let renderer: MarkdownPreviewRendering
    private let versionQueue = DispatchQueue(label: "Smux.MarkdownPreviewPipeline.version")
    private var latestRequestedVersions: [DocumentSession.ID: Int] = [:]

    init(renderer: MarkdownPreviewRendering = BasicMarkdownPreviewRenderer()) {
        self.renderer = renderer
    }

    func render(documentID: DocumentSession.ID, text: String, version: Int) async throws -> PreviewState {
        recordRequestedVersion(version, for: documentID)

        let renderResult = renderer.render(text)
        let stale = isStale(version, for: documentID)
        var errors = renderResult.errors

        if stale {
            errors.append(
                PreviewRenderError(
                    id: UUID(),
                    message: "Stale preview render ignored for version \(version).",
                    sourceRange: nil
                )
            )
        }

        return PreviewState(
            id: PreviewState.ID(),
            sourceDocumentID: documentID,
            renderVersion: version,
            sanitizedMarkdown: stale ? nil : renderResult.sanitizedMarkdown,
            mermaidBlocks: stale ? [] : renderResult.mermaidBlocks,
            errors: errors,
            zoom: 1,
            scrollAnchor: nil
        )
    }

    func invalidate(documentID: DocumentSession.ID) {
        _ = versionQueue.sync {
            latestRequestedVersions.removeValue(forKey: documentID)
        }
    }

    private func recordRequestedVersion(_ version: Int, for documentID: DocumentSession.ID) {
        versionQueue.sync {
            latestRequestedVersions[documentID] = max(latestRequestedVersions[documentID] ?? version, version)
        }
    }

    private func isStale(_ version: Int, for documentID: DocumentSession.ID) -> Bool {
        versionQueue.sync {
            version < (latestRequestedVersions[documentID] ?? version)
        }
    }
}
