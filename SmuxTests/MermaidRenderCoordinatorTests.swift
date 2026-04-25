import XCTest
@testable import Smux

final class MermaidRenderCoordinatorTests: XCTestCase {
    func testRenderReturnsDeterministicSanitizedPlaceholderArtifact() async throws {
        let coordinator = MermaidRenderCoordinator()
        let block = makeBlock(
            source: """
            graph LR
                A["<start>"] --> B["done & safe"]
            """
        )

        let firstArtifact = try await coordinator.render(block: block)
        let secondArtifact = try await coordinator.render(block: block)

        XCTAssertEqual(firstArtifact, secondArtifact)
        XCTAssertEqual(
            firstArtifact,
            .sanitizedHTML(
                """
                <pre class="mermaid-placeholder" data-diagram-type="graph"><code>graph LR
                    A[&quot;&lt;start&gt;&quot;] --&gt; B[&quot;done &amp; safe&quot;]</code></pre>
                """
            )
        )
    }

    func testRenderThrowsClearErrorForEmptySource() async {
        let coordinator = MermaidRenderCoordinator()
        let block = makeBlock(source: "  \n\t")

        do {
            _ = try await coordinator.render(block: block)
            XCTFail("Expected empty Mermaid source to throw.")
        } catch {
            XCTAssertEqual(error as? MermaidRenderError, .emptySource)
        }
    }

    func testRenderThrowsClearErrorForUnsupportedSource() async {
        let coordinator = MermaidRenderCoordinator()
        let block = makeBlock(source: "notMermaid A --> B")

        do {
            _ = try await coordinator.render(block: block)
            XCTFail("Expected unsupported Mermaid source to throw.")
        } catch {
            XCTAssertEqual(error as? MermaidRenderError, .unsupportedSyntax("notMermaid A --> B"))
        }
    }

    func testCancelAllIsSafeBeforeAndAfterRender() async throws {
        let coordinator = MermaidRenderCoordinator()

        coordinator.cancelAll()
        _ = try await coordinator.render(block: makeBlock(source: "sequenceDiagram\nAlice->>Bob: Hi"))
        coordinator.cancelAll()
    }

    func testMermaidBlockStateDecodesSnapshotsWithoutSource() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "sourceRange": {
            "startLine": 1,
            "endLine": 2
          },
          "status": "pending"
        }
        """

        let block = try JSONDecoder().decode(MermaidBlockState.self, from: Data(json.utf8))

        XCTAssertEqual(block.source, "")
        XCTAssertEqual(block.status, .pending)
        XCTAssertNil(block.artifact)
        XCTAssertNil(block.errorMessage)
    }

    private func makeBlock(source: String) -> MermaidBlockState {
        MermaidBlockState(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceRange: SourceRange(startLine: 1, endLine: 2),
            source: source,
            status: .pending,
            artifact: nil,
            errorMessage: nil
        )
    }
}
