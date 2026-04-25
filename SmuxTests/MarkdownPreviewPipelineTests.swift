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

    func testLeavesMermaidAsEscapedCodeAndDoesNotCreateMermaidBlocksYet() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let markdown = """
        ```mermaid
        graph LR
            A --> B
        ```
        """

        let state = try await pipeline.render(documentID: DocumentSession.ID(), text: markdown, version: 1)
        let html = try XCTUnwrap(state.sanitizedMarkdown?.html)

        XCTAssertTrue(state.mermaidBlocks.isEmpty)
        XCTAssertTrue(html.contains("<pre><code class=\"language-mermaid\">"))
        XCTAssertTrue(html.contains("A --&gt; B"))
    }

    func testModelsStaleRenderResultsByVersion() async throws {
        let pipeline = MarkdownPreviewPipeline()
        let documentID = DocumentSession.ID()

        let current = try await pipeline.render(documentID: documentID, text: "# Current", version: 2)
        let stale = try await pipeline.render(documentID: documentID, text: "# Stale", version: 1)

        XCTAssertNotNil(current.sanitizedMarkdown)
        XCTAssertNil(stale.sanitizedMarkdown)
        XCTAssertEqual(stale.renderVersion, 1)
        XCTAssertTrue(stale.errors.contains { $0.message.contains("Stale preview render ignored") })

        pipeline.invalidate(documentID: documentID)
        let reset = try await pipeline.render(documentID: documentID, text: "# Reset", version: 1)
        XCTAssertNotNil(reset.sanitizedMarkdown)
        XCTAssertTrue(reset.errors.isEmpty)
    }
}
