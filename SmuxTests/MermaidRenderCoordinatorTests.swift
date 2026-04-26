import XCTest
@testable import Smux

final class MermaidRenderCoordinatorTests: XCTestCase {
    func testRenderUsesInjectedResourceAndRendererForValidMermaidBlock() async throws {
        let resource = MermaidJavaScriptResource(
            fileName: "mermaid.min.js",
            source: "window.mermaid = { render: function() {} };"
        )
        let expectedArtifact = MermaidRenderArtifact.sanitizedSVG("<svg data-rendered-by=\"fake-mermaid\"></svg>")
        let renderer = RecordingMermaidRenderer(artifact: expectedArtifact)
        let coordinator = MermaidRenderCoordinator(
            resourceProvider: StaticMermaidResourceProvider(resource: resource),
            renderer: renderer
        )
        let block = makeBlock(
            source: """
            graph LR\r
                A["<start>"] --> B["done & safe"]
            """
        )

        let artifact = try await coordinator.render(block: block)
        let request = try XCTUnwrap(renderer.requests.first)

        XCTAssertEqual(artifact, expectedArtifact)
        XCTAssertEqual(renderer.requests.count, 1)
        XCTAssertEqual(request.blockID, block.id)
        XCTAssertEqual(request.sourceRange, block.sourceRange)
        XCTAssertEqual(request.source, "graph LR\n    A[\"<start>\"] --> B[\"done & safe\"]")
        XCTAssertEqual(request.diagramType, "graph")
        XCTAssertEqual(request.javaScriptResource, resource)
    }

    func testRenderThrowsLocalizedErrorWhenOfficialBundleIsMissing() async {
        let renderer = RecordingMermaidRenderer(artifact: .sanitizedSVG("<svg></svg>"))
        let coordinator = MermaidRenderCoordinator(
            resourceProvider: MissingMermaidResourceProvider(),
            renderer: renderer
        )

        do {
            _ = try await coordinator.render(block: makeBlock(source: "graph LR\nA --> B"))
            XCTFail("Expected missing Mermaid bundle to throw.")
        } catch {
            let renderError = error as? MermaidRenderError
            let expectedMessage = "Official Mermaid JavaScript bundle is missing. Add mermaid.min.js or mermaid.js to the app target resources for offline rendering."

            XCTAssertEqual(renderError, .missingOfficialMermaidBundle(["mermaid.min.js", "mermaid.js"]))
            XCTAssertEqual(error.localizedDescription, expectedMessage)
            XCTAssertTrue(renderer.requests.isEmpty)
        }
    }

    func testFallbackArtifactIsExplicitFallbackHTMLNotOfficialSVG() throws {
        let coordinator = MermaidRenderCoordinator()
        let block = makeBlock(
            source: """
            graph LR
                A["<start>"] --> B["done & safe"]
            """
        )

        let artifact = try coordinator.fallbackArtifact(for: block)

        switch artifact {
        case .sanitizedHTML(let html):
            XCTAssertTrue(html.contains("class=\"mermaid-fallback-source\""))
            XCTAssertTrue(html.contains("data-renderer=\"fallback\""))
            XCTAssertTrue(html.contains("data-diagram-type=\"graph\""))
            XCTAssertTrue(html.contains("A[&quot;&lt;start&gt;&quot;] --&gt; B[&quot;done &amp; safe&quot;]"))
            XCTAssertFalse(html.contains("mermaid-placeholder"))
            XCTAssertFalse(html.localizedCaseInsensitiveContains("official"))
        case .sanitizedSVG:
            XCTFail("Fallback Mermaid output must not be represented as official rendered SVG.")
        }
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
        let coordinator = MermaidRenderCoordinator(
            resourceProvider: StaticMermaidResourceProvider(
                resource: MermaidJavaScriptResource(fileName: "mermaid.min.js", source: "official bundle")
            ),
            renderer: RecordingMermaidRenderer(artifact: .sanitizedSVG("<svg></svg>"))
        )

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

private struct StaticMermaidResourceProvider: MermaidJavaScriptResourceProviding {
    var resource: MermaidJavaScriptResource

    func loadMermaidJavaScriptResource() throws -> MermaidJavaScriptResource {
        resource
    }
}

private struct MissingMermaidResourceProvider: MermaidJavaScriptResourceProviding {
    func loadMermaidJavaScriptResource() throws -> MermaidJavaScriptResource {
        throw MermaidRenderError.missingOfficialMermaidBundle(["mermaid.min.js", "mermaid.js"])
    }
}

private final class RecordingMermaidRenderer: MermaidDiagramRendering {
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
