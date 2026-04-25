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
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<h2>Section</h2>"))
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
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(html.contains("let tag = &quot;&lt;main&gt;&quot;"))
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
        XCTAssertTrue(html.contains("<h1>Diagrams</h1>"))
        XCTAssertTrue(html.contains("data-mermaid-block-id=\"\(state.mermaidBlocks[0].id.uuidString)\""))
        XCTAssertTrue(html.contains("data-mermaid-block-id=\"\(state.mermaidBlocks[1].id.uuidString)\""))
        XCTAssertFalse(html.contains("language-mmd"))
        XCTAssertFalse(html.contains("language-mermaid"))
        XCTAssertFalse(html.contains("Alice-&gt;&gt;Bob"))
        XCTAssertFalse(html.contains("A --&gt; B"))
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
}
