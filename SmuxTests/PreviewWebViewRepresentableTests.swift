import XCTest
import WebKit
@testable import Smux

final class PreviewWebViewRepresentableTests: XCTestCase {
    func testBuildsSelfContainedHTMLForNilState() {
        let html = PreviewWebViewHTMLBuilder.makeHTML(state: nil)

        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("No preview available"))
        XCTAssertFalse(html.contains("data-mermaid-pan-surface"))
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

    func testShowsRenderingAndFailedMermaidStatesWithEscapedDetails() {
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

        XCTAssertTrue(html.contains("Rendering"))
        XCTAssertTrue(html.contains("Failed"))
        XCTAssertTrue(html.contains("mermaid-render-source"))
        XCTAssertTrue(html.contains("A[&lt;start&gt;] --&gt; B"))
        XCTAssertTrue(html.contains("Unsupported &lt;diagram&gt;"))
        XCTAssertFalse(html.contains("A[<start>]"))
        XCTAssertFalse(html.contains("Unsupported <diagram>"))
    }

    func testLoadsOfficialMermaidBundleFromMainAppResourcesForOfflineRendering() throws {
        let bundleURL = try XCTUnwrap(Bundle.main.url(forResource: "mermaid.min", withExtension: "js"))
        let resource = try BundledMermaidJavaScriptResourceProvider(bundle: .main)
            .loadMermaidJavaScriptResource()

        XCTAssertTrue(bundleURL.isFileURL)
        XCTAssertEqual(bundleURL.lastPathComponent, "mermaid.min.js")
        XCTAssertEqual(resource.fileName, "mermaid.min.js")
        XCTAssertFalse(resource.source.isEmpty)
        XCTAssertTrue(resource.source.contains("globalThis[\"mermaid\"]"))
        XCTAssertFalse(resource.source.contains("cdn.jsdelivr"))
        XCTAssertFalse(resource.source.contains("unpkg.com"))
    }

    func testInlinesOfflineMermaidBundleForPendingBlocksWithoutExternalScriptSource() {
        let blockID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let placeholder = """
        <div class="mermaid-preview-placeholder" data-mermaid-block-id="\(blockID.uuidString)" data-source-start-line="2" data-source-end-line="4"></div>
        """
        let state = makeState(
            sanitizedMarkdown: SanitizedMarkdown(html: "<h1>Diagram</h1>\n\(placeholder)"),
            mermaidBlocks: [
                MermaidBlockState(
                    id: blockID,
                    sourceRange: SourceRange(startLine: 2, endLine: 4),
                    source: "flowchart LR\nA --> B",
                    status: .pending,
                    artifact: nil,
                    errorMessage: nil
                )
            ]
        )

        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)

        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("script-src 'unsafe-inline'"))
        XCTAssertTrue(html.contains("globalThis[\"mermaid\"]"))
        XCTAssertTrue(html.contains("window.mermaid.initialize"))
        XCTAssertTrue(html.contains("securityLevel: \"strict\""))
        XCTAssertTrue(html.contains("window.mermaid.run({ nodes: blocks })"))
        XCTAssertTrue(html.contains("<pre class=\"mermaid mermaid-render-source\">flowchart LR\nA --&gt; B</pre>"))
        XCTAssertTrue(html.contains("Rendering"))
        XCTAssertFalse(html.contains("<script src="))
        XCTAssertFalse(html.contains("cdn.jsdelivr"))
        XCTAssertFalse(html.contains("unpkg.com"))
    }

    func testClampsPreviewZoomInGeneratedHTML() {
        let overZoomed = PreviewWebViewHTMLBuilder.makeHTML(
            state: makeState(sanitizedMarkdown: SanitizedMarkdown(html: "<p>Body</p>"), zoom: 8)
        )
        let underZoomed = PreviewWebViewHTMLBuilder.makeHTML(
            state: makeState(sanitizedMarkdown: SanitizedMarkdown(html: "<p>Body</p>"), zoom: 0.1)
        )

        XCTAssertTrue(overZoomed.contains("--preview-zoom: 3.0;"))
        XCTAssertTrue(underZoomed.contains("--preview-zoom: 0.5;"))
    }

    func testAddsMermaidDiagramZoomControlsAndPanSurface() {
        let blockID = UUID(uuidString: "00000000-0000-0000-0000-000000000024")!
        let placeholder = """
        <div class="mermaid-preview-placeholder" data-mermaid-block-id="\(blockID.uuidString)" data-source-start-line="2" data-source-end-line="4"></div>
        """
        let state = makeState(
            sanitizedMarkdown: SanitizedMarkdown(html: "<h1>Diagram</h1>\n\(placeholder)"),
            mermaidBlocks: [
                makeMermaidBlock(
                    id: blockID,
                    startLine: 2,
                    endLine: 4,
                    source: "flowchart LR\nA --> B"
                )
            ]
        )

        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)

        XCTAssertTrue(html.contains("class=\"mermaid-controls\""))
        XCTAssertTrue(html.contains("data-mermaid-zoom-out"))
        XCTAssertTrue(html.contains("data-mermaid-zoom-reset"))
        XCTAssertTrue(html.contains("data-mermaid-zoom-in"))
        XCTAssertTrue(html.contains("data-mermaid-pan-surface"))
        XCTAssertTrue(html.contains("--mermaid-diagram-zoom"))
        XCTAssertTrue(html.contains("scrollLeft = startScrollLeft"))
    }

    @MainActor
    func testWebViewRendersCommonMermaidDiagramsOffline() async throws {
        let blocks = [
            makeMermaidBlock(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                startLine: 2,
                endLine: 5,
                source: """
                flowchart LR
                    A[Start] --> B{Ready?}
                    B --> C[Render]
                """
            ),
            makeMermaidBlock(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
                startLine: 7,
                endLine: 10,
                source: """
                sequenceDiagram
                    participant Editor
                    participant Preview
                    Editor->>Preview: Update
                """
            ),
            makeMermaidBlock(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
                startLine: 12,
                endLine: 15,
                source: """
                stateDiagram-v2
                    [*] --> Pending
                    Pending --> Rendered
                """
            )
        ]
        let placeholders = blocks.map { block in
            """
            <div class="mermaid-preview-placeholder" data-mermaid-block-id="\(block.id.uuidString)" data-source-start-line="\(block.sourceRange.startLine)" data-source-end-line="\(block.sourceRange.endLine)"></div>
            """
        }.joined(separator: "\n")
        let state = makeState(
            sanitizedMarkdown: SanitizedMarkdown(html: "<h1>Diagrams</h1>\n\(placeholders)"),
            mermaidBlocks: blocks
        )
        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)
        XCTAssertFalse(html.contains("<script src="))
        XCTAssertFalse(html.contains("cdn.jsdelivr"))
        XCTAssertFalse(html.contains("unpkg.com"))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let navigationDelegate = PreviewWebViewNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
        let loadFinished = expectation(description: "Preview WebView load finished")
        navigationDelegate.didFinish = { loadFinished.fulfill() }
        navigationDelegate.didFail = { error in
            XCTFail("Preview WebView load failed: \(error)")
            loadFinished.fulfill()
        }

        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loadFinished], timeout: 5)

        let status = try await waitForMermaidRender(in: webView, expectedDiagramCount: blocks.count)
        XCTAssertEqual(status.svgCount, blocks.count)
        XCTAssertEqual(status.failedCount, 0)
        XCTAssertEqual(status.externalScriptCount, 0)
        XCTAssertTrue(status.badges.allSatisfy { $0 == "Rendered" })
    }

    @MainActor
    func testNavigationPolicyAllowsInternalAnchorLinksAndBlocksExternalLinks() {
        XCTAssertEqual(
            PreviewWebViewRepresentable.Coordinator.policy(for: .linkActivated, url: URL(string: "#section")),
            .allow
        )
        XCTAssertEqual(
            PreviewWebViewRepresentable.Coordinator.policy(for: .linkActivated, url: URL(string: "about:blank#section")),
            .allow
        )
        XCTAssertEqual(
            PreviewWebViewRepresentable.Coordinator.policy(for: .linkActivated, url: URL(string: "guide.md#section")),
            .cancel
        )
        XCTAssertEqual(
            PreviewWebViewRepresentable.Coordinator.policy(for: .linkActivated, url: URL(string: "https://example.com/#section")),
            .cancel
        )
        XCTAssertEqual(
            PreviewWebViewRepresentable.Coordinator.policy(for: .other, url: URL(string: "https://example.com/")),
            .allow
        )
    }

    @MainActor
    private func waitForMermaidRender(
        in webView: WKWebView,
        expectedDiagramCount: Int
    ) async throws -> MermaidWebViewStatus {
        var latestStatus = MermaidWebViewStatus(
            svgCount: 0,
            failedCount: 0,
            externalScriptCount: 0,
            badges: []
        )

        for _ in 0..<50 {
            latestStatus = try await mermaidStatus(in: webView)
            if latestStatus.svgCount == expectedDiagramCount,
               latestStatus.failedCount == 0,
               latestStatus.badges.count == expectedDiagramCount,
               latestStatus.badges.allSatisfy({ $0 == "Rendered" }) {
                return latestStatus
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTFail("Timed out waiting for Mermaid render status: \(latestStatus)")
        return latestStatus
    }

    @MainActor
    private func mermaidStatus(in webView: WKWebView) async throws -> MermaidWebViewStatus {
        let script = """
        JSON.stringify({
            svgCount: document.querySelectorAll(".mermaid-block svg").length,
            failedCount: document.querySelectorAll(".mermaid-block--failed").length,
            externalScriptCount: Array.from(document.scripts).filter((script) => script.src).length,
            badges: Array.from(document.querySelectorAll(".mermaid-badge")).map((badge) => badge.textContent)
        })
        """
        let value = try await webView.evaluateJavaScript(script)
        let json = try XCTUnwrap(value as? String)
        return try JSONDecoder().decode(MermaidWebViewStatus.self, from: Data(json.utf8))
    }

    private func makeMermaidBlock(
        id: UUID,
        startLine: Int,
        endLine: Int,
        source: String
    ) -> MermaidBlockState {
        MermaidBlockState(
            id: id,
            sourceRange: SourceRange(startLine: startLine, endLine: endLine),
            source: source,
            status: .pending,
            artifact: nil,
            errorMessage: nil
        )
    }

    private func makeState(
        sanitizedMarkdown: SanitizedMarkdown?,
        mermaidBlocks: [MermaidBlockState] = [],
        errors: [PreviewRenderError] = [],
        zoom: Double = PreviewState.defaultZoom
    ) -> PreviewState {
        PreviewState(
            id: PreviewState.ID(),
            sourceDocumentID: DocumentSession.ID(),
            renderVersion: 1,
            sanitizedMarkdown: sanitizedMarkdown,
            mermaidBlocks: mermaidBlocks,
            errors: errors,
            zoom: zoom,
            scrollAnchor: nil
        )
    }
}

private struct MermaidWebViewStatus: Decodable, CustomStringConvertible {
    var svgCount: Int
    var failedCount: Int
    var externalScriptCount: Int
    var badges: [String]

    var description: String {
        "svgCount=\(svgCount), failedCount=\(failedCount), externalScriptCount=\(externalScriptCount), badges=\(badges)"
    }
}

@MainActor
private final class PreviewWebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinish: (() -> Void)?
    var didFail: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        didFail?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        didFail?(error)
    }
}
