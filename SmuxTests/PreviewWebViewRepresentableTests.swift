import XCTest
@testable import Smux

final class PreviewWebViewRepresentableTests: XCTestCase {
    func testBuildsSelfContainedHTMLForNilState() {
        let html = PreviewWebViewHTMLBuilder.makeHTML(state: nil)

        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("No preview available"))
    }

    func testShowsUnavailableStateAndEscapesRenderErrorsWhenMarkdownIsMissing() {
        let state = makeState(
            sanitizedMarkdown: nil,
            errors: [
                PreviewRenderError(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                    message: "Bad <tag> & \"quote\"",
                    sourceRange: SourceRange(startLine: 4, endLine: 5)
                )
            ]
        )

        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)

        XCTAssertTrue(html.contains("Preview could not be rendered"))
        XCTAssertTrue(html.contains("Bad &lt;tag&gt; &amp; &quot;quote&quot; Lines 4-5."))
        XCTAssertFalse(html.contains("Bad <tag>"))
    }

    func testPreservesSanitizedMarkdownAndInlinesRenderedMermaidArtifact() {
        let blockID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let placeholder = """
        <div class="mermaid-preview-placeholder" data-mermaid-block-id="\(blockID.uuidString)" data-source-start-line="2" data-source-end-line="4"></div>
        """
        let state = makeState(
            sanitizedMarkdown: SanitizedMarkdown(html: "<h1>Title</h1>\n\(placeholder)\n<p>After</p>"),
            mermaidBlocks: [
                MermaidBlockState(
                    id: blockID,
                    sourceRange: SourceRange(startLine: 2, endLine: 4),
                    source: "graph LR\nA --> B",
                    status: .rendered,
                    artifact: .sanitizedHTML("<pre class=\"mermaid-placeholder\"><code>graph LR</code></pre>"),
                    errorMessage: nil
                )
            ]
        )

        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<pre class=\"mermaid-placeholder\"><code>graph LR</code></pre>"))
        XCTAssertTrue(html.contains("Mermaid diagram, lines 2-4"))
        XCTAssertTrue(html.contains("Rendered"))
        XCTAssertTrue(html.contains("<p>After</p>"))
        XCTAssertFalse(html.contains("mermaid-preview-placeholder"))
    }

    func testShowsPendingAndFailedMermaidStatesWithEscapedDetails() {
        let pendingID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let failedID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let state = makeState(
            sanitizedMarkdown: SanitizedMarkdown(html: "<p>Body</p>"),
            mermaidBlocks: [
                MermaidBlockState(
                    id: pendingID,
                    sourceRange: SourceRange(startLine: 8, endLine: 10),
                    source: "graph LR\nA[<start>] --> B",
                    status: .pending,
                    artifact: nil,
                    errorMessage: nil
                ),
                MermaidBlockState(
                    id: failedID,
                    sourceRange: SourceRange(startLine: 12, endLine: 13),
                    source: "",
                    status: .failed,
                    artifact: nil,
                    errorMessage: "Unsupported <diagram>"
                )
            ]
        )

        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)

        XCTAssertTrue(html.contains("Pending"))
        XCTAssertTrue(html.contains("Failed"))
        XCTAssertTrue(html.contains("A[&lt;start&gt;] --&gt; B"))
        XCTAssertTrue(html.contains("Unsupported &lt;diagram&gt;"))
        XCTAssertFalse(html.contains("Unsupported <diagram>"))
    }

    private func makeState(
        sanitizedMarkdown: SanitizedMarkdown?,
        mermaidBlocks: [MermaidBlockState] = [],
        errors: [PreviewRenderError] = []
    ) -> PreviewState {
        PreviewState(
            id: PreviewState.ID(),
            sourceDocumentID: DocumentSession.ID(),
            renderVersion: 1,
            sanitizedMarkdown: sanitizedMarkdown,
            mermaidBlocks: mermaidBlocks,
            errors: errors,
            zoom: 1,
            scrollAnchor: nil
        )
    }
}
