import XCTest
@testable import Smux

final class MarkdownPreviewPipelineTests: XCTestCase {
    func testRendersMarkdownMVPBlocksAndLinks() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let documentID = DocumentSession.ID()
        let markdown = """
        # Title

        ## Section

        - One
        - [Two](https://example.com/path?a=1&b=2)

        1. First
        2. Second

        > Quote [mail](mailto:test@example.com)
        """

        let state = try await pipeline.render(documentID: documentID, text: markdown, version: 7)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertEqual(state.sourceDocumentID, documentID)
        XCTAssertEqual(state.renderVersion, 7)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.mermaidBlocks.isEmpty)
        XCTAssertTrue(html.contains("<h1 id=\"title\">Title</h1>"))
        XCTAssertTrue(html.contains("<h2 id=\"section\">Section</h2>"))
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>One</li>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com/path?a=1&amp;b=2\" rel=\"noopener noreferrer\">Two</a>"))
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<li>First</li>"))
        XCTAssertTrue(html.contains("<blockquote>Quote <a href=\"mailto:test@example.com\" rel=\"noopener noreferrer\">mail</a></blockquote>"))
    }

    func testRendersTablesAndFencedCodeBlocksWithEscapedContent() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        | Name | Value |
        | --- | --- |
        | Swift | <safe> |

        ```swift
        let tag = "<main>"
        ```
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>&lt;safe&gt;</td>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\" data-language=\"swift\">"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--keyword\">let</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--string\">&quot;&lt;main&gt;&quot;</span>"))
    }

    func testHighlightsFencedCodeBlocksWithoutExternalDependency() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        ```swift
        // greet
        let tag = "<main>"
        if tag.isEmpty { return }
        ```

        ```json
        {"name": "Smux", "enabled": true, "delta": -42}
        ```
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--comment\">// greet</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--keyword\">let</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--keyword\">if</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--keyword\">return</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--string\">&quot;&lt;main&gt;&quot;</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--property\">&quot;name&quot;</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--literal\">true</span>"))
        XCTAssertTrue(html.contains("<span class=\"code-token code-token--number\">-42</span>"))
        XCTAssertFalse(html.contains("<script"))
    }

    func testGeneratesStableGitHubStyleHeadingAnchorsAndInternalLinks() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        # Hello, World!
        ## Hello World
        ### Hello World
        # [API Guide](https://example.com/api)
        # C# Guide

        [Jump](#hello-world-1)
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(html.contains("<h1 id=\"hello-world\">Hello, World!</h1>"))
        XCTAssertTrue(html.contains("<h2 id=\"hello-world-1\">Hello World</h2>"))
        XCTAssertTrue(html.contains("<h3 id=\"hello-world-2\">Hello World</h3>"))
        XCTAssertTrue(html.contains("<h1 id=\"api-guide\"><a href=\"https://example.com/api\" rel=\"noopener noreferrer\">API Guide</a></h1>"))
        XCTAssertTrue(html.contains("<h1 id=\"c-guide\">C# Guide</h1>"))
        XCTAssertTrue(html.contains("<a href=\"#hello-world-1\" rel=\"noopener noreferrer\">Jump</a>"))
    }

    func testSanitizesHTMLAndUnsafeLinks() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        # <script>alert('x')</script>

        [bad](javascript:alert)
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("href=\"javascript:alert\""))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("[bad](javascript:alert)"))
    }

    func testExtractsMermaidFenceIntoPreviewStateAndPlaceholder() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        ```mermaid
        graph LR
            A --> B
        ```
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)
        let block = try XCTUnwrap(state.mermaidBlocks.first)

        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertEqual(state.mermaidBlocks.count, 1)
        XCTAssertEqual(block.sourceRange, SourceRange(startLine: 1, endLine: 4))
        XCTAssertEqual(
            block.source,
            """
            graph LR
                A --> B
            """
        )
        XCTAssertEqual(block.status, .pending)
        XCTAssertNil(block.artifact)
        XCTAssertNil(block.errorMessage)
        XCTAssertTrue(html.contains("data-mermaid-block-id=\"\(block.id.uuidString)\""))
        XCTAssertTrue(html.contains("data-source-start-line=\"1\""))
        XCTAssertTrue(html.contains("data-source-end-line=\"4\""))
        XCTAssertFalse(html.contains("<pre><code class=\"language-mermaid\">"))
        XCTAssertFalse(html.contains("A --&gt; B"))
    }

    func testExtractsMmdAndTildeMermaidFencesWithoutDuplicatingSourceCodeHTML() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        # Diagrams

        ```mmd
        sequenceDiagram
        Alice->>Bob: Hi
        ```

        ~~~mermaid
        graph TD
        A --> B
        ~~~
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertEqual(state.mermaidBlocks.count, 2)
        XCTAssertEqual(state.mermaidBlocks[0].sourceRange, SourceRange(startLine: 3, endLine: 6))
        XCTAssertEqual(state.mermaidBlocks[0].source, "sequenceDiagram\nAlice->>Bob: Hi")
        XCTAssertEqual(state.mermaidBlocks[1].sourceRange, SourceRange(startLine: 8, endLine: 11))
        XCTAssertEqual(state.mermaidBlocks[1].source, "graph TD\nA --> B")
        XCTAssertTrue(html.contains("<h1 id=\"diagrams\">Diagrams</h1>"))
        XCTAssertTrue(html.contains("data-mermaid-block-id=\"\(state.mermaidBlocks[0].id.uuidString)\""))
        XCTAssertTrue(html.contains("data-mermaid-block-id=\"\(state.mermaidBlocks[1].id.uuidString)\""))
        XCTAssertFalse(html.contains("language-mmd"))
        XCTAssertFalse(html.contains("language-mermaid"))
        XCTAssertFalse(html.contains("Alice-&gt;&gt;Bob"))
        XCTAssertFalse(html.contains("A --&gt; B"))
    }

    func testRepresentativeMermaidFixtureExtractsCommonDiagramTypesAndBuildsRenderInputs() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = try loadFixture(named: "representative_mermaid.md")
        let expectedSources = [
            """
            flowchart LR
                Start([Start]) --> Decision{Ready?}
                Decision -- Yes --> Render[Render preview]
                Decision -- No --> Fix[Edit source]
            """,
            """
            sequenceDiagram
                participant Editor
                participant Preview
                Editor->>Preview: Markdown changed
                Preview-->>Editor: Sanitized HTML
            """,
            """
            stateDiagram-v2
                [*] --> Pending
                Pending --> Rendering
                Rendering --> Rendered
                Rendering --> Failed
            """,
            """
            gantt
                title Preview P0-4
                dateFormat  YYYY-MM-DD
                section Offline
                Bundle linked       :done, 2026-04-26, 1d
                Fixture coverage    :active, 2026-04-26, 1d
            """,
            """
            classDiagram
                class MarkdownPreviewPipeline
                class MermaidRenderCoordinator
                MarkdownPreviewPipeline --> MermaidRenderCoordinator : blocks
            """,
            """
            erDiagram
                DOCUMENT ||--o{ MERMAID_BLOCK : contains
                MERMAID_BLOCK {
                    string id
                    string source
                    string status
                }
            """
        ]
        let expectedDiagramTypes = [
            "flowchart",
            "sequenceDiagram",
            "stateDiagram-v2",
            "gantt",
            "classDiagram",
            "erDiagram"
        ]

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertEqual(state.mermaidBlocks.map(\.source), expectedSources)
        XCTAssertTrue(html.contains("<h1 id=\"mermaid-preview-fixture\">Mermaid Preview Fixture</h1>"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<pre><code class=\"language-mermaid\">"))
        XCTAssertFalse(html.contains("Decision -- Yes --&gt; Render"))
        XCTAssertFalse(html.contains("Editor-&gt;&gt;Preview"))
        XCTAssertFalse(html.contains("DOCUMENT ||--o{ MERMAID_BLOCK"))

        for block in state.mermaidBlocks {
            XCTAssertEqual(block.status, .pending)
            XCTAssertNil(block.artifact)
            XCTAssertNil(block.errorMessage)
            XCTAssertTrue(html.contains("data-mermaid-block-id=\"\(block.id.uuidString)\""))
            XCTAssertTrue(html.contains("data-source-start-line=\"\(block.sourceRange.startLine)\""))
            XCTAssertTrue(html.contains("data-source-end-line=\"\(block.sourceRange.endLine)\""))
        }

        let resource = MermaidJavaScriptResource(fileName: "mermaid.min.js", source: "official bundle")
        let renderer = MarkdownPreviewRecordingMermaidRenderer(artifact: .sanitizedSVG("<svg></svg>"))
        let coordinator = MermaidRenderCoordinator(
            resourceProvider: MarkdownPreviewStaticMermaidResourceProvider(resource: resource),
            renderer: renderer
        )

        for block in state.mermaidBlocks {
            _ = try await coordinator.render(block: block)
        }

        XCTAssertEqual(renderer.requests.map(\.source), expectedSources)
        XCTAssertEqual(renderer.requests.map(\.diagramType), expectedDiagramTypes)
        XCTAssertTrue(renderer.requests.allSatisfy { $0.javaScriptResource == resource })
    }

    func testUnclosedMermaidFenceProducesDeterministicBlockAndError() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        Before

        ```mermaid
        graph LR
        A --> B
        """

        let first = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let second = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let firstHTML = try XCTUnwrap(first.sanitizedMarkdown?.html)
        let secondHTML = try XCTUnwrap(second.sanitizedMarkdown?.html)
        let block = try XCTUnwrap(first.mermaidBlocks.first)
        let error = try XCTUnwrap(first.errors.first)

        XCTAssertEqual(first.mermaidBlocks, second.mermaidBlocks)
        XCTAssertEqual(first.errors, second.errors)
        XCTAssertEqual(firstHTML, secondHTML)
        XCTAssertEqual(first.mermaidBlocks.count, 1)
        XCTAssertEqual(block.sourceRange, SourceRange(startLine: 3, endLine: 5))
        XCTAssertEqual(block.source, "graph LR\nA --> B")
        XCTAssertEqual(block.errorMessage, "Unclosed Mermaid code fence.")
        XCTAssertEqual(first.errors.count, 1)
        XCTAssertEqual(error.message, "Unclosed Mermaid code fence.")
        XCTAssertEqual(error.sourceRange, SourceRange(startLine: 3, endLine: 5))
        XCTAssertTrue(firstHTML.contains("<p>Before</p>"))
        XCTAssertTrue(firstHTML.contains("data-mermaid-block-id=\"\(block.id.uuidString)\""))
        XCTAssertFalse(firstHTML.contains("<pre><code class=\"language-mermaid\">"))
    }

    func testModelsStaleRenderResultsByVersion() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let documentID = DocumentSession.ID()

        let current = try await pipeline.render(documentID: documentID, text: "# Current", version: 2)
        let stale = try await pipeline.render(
            documentID: documentID,
            text: """
            ```mermaid
            graph LR
            A --> B
            ```
            """,
            version: 1
        )

        XCTAssertNotNil(current.sanitizedMarkdown)
        XCTAssertNil(stale.sanitizedMarkdown)
        XCTAssertTrue(stale.mermaidBlocks.isEmpty)
        XCTAssertEqual(stale.renderVersion, 1)
        XCTAssertTrue(stale.errors.contains { $0.message.contains("Stale preview render ignored") })

        pipeline.invalidate(documentID: documentID)
        let reset = try await pipeline.render(documentID: documentID, text: "# Reset", version: 1)
        XCTAssertNotNil(reset.sanitizedMarkdown)
        XCTAssertTrue(reset.errors.isEmpty)
    }

    private func loadFixture(named fileName: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let fixtureURL = try XCTUnwrap(
            bundle.url(
                forResource: fileName,
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        )

        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }
}

private struct MarkdownPreviewStaticMermaidResourceProvider: MermaidJavaScriptResourceProviding {
    var resource: MermaidJavaScriptResource

    func loadMermaidJavaScriptResource() throws -> MermaidJavaScriptResource {
        resource
    }
}

private final class MarkdownPreviewRecordingMermaidRenderer: MermaidDiagramRendering {
    private let artifact: MermaidRenderArtifact
    private(set) var requests: [MermaidRenderRequest] = []

    init(artifact: MermaidRenderArtifact) {
        self.artifact = artifact
    }

    func render(_ request: MermaidRenderRequest) async throws -> MermaidRenderArtifact {
        requests.append(request)
        return artifact
    }
}
