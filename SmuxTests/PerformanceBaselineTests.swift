import XCTest
@testable import Smux

final class PerformanceBaselineTests: XCTestCase {
    func testLargeMarkdownPreviewRenderPerformance() {
        let markdown = Self.makeLargeMarkdownDocument(sectionCount: 300, mermaidBlockCount: 24)
        let renderer = BasicMarkdownPreviewRenderer()
        let warmup = renderer.render(markdown)

        XCTAssertTrue(warmup.errors.isEmpty)
        XCTAssertEqual(warmup.mermaidBlocks.count, 24)
        XCTAssertGreaterThan(warmup.sanitizedMarkdown.html.count, 80_000)

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let result = renderer.render(markdown)

            XCTAssertTrue(result.errors.isEmpty)
            XCTAssertEqual(result.mermaidBlocks.count, 24)
            XCTAssertGreaterThan(result.sanitizedMarkdown.html.count, 80_000)
        }
    }

    func testTerminalOutputAppendAndScrollbackPerformance() {
        let chunks = Self.makeTerminalOutputChunks(chunkCount: 40, linesPerChunk: 50)
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            var buffer = TerminalOutputBuffer(maximumCharacterCount: 50_000)

            for chunk in chunks {
                buffer.append(chunk)
            }

            let displayText = buffer.displayText
            let displayRuns = buffer.displayRuns

            XCTAssertLessThanOrEqual(buffer.text.count, 50_000)
            XCTAssertLessThanOrEqual(displayText.count, 50_000)
            XCTAssertFalse(displayText.contains("\u{1B}"))
            XCTAssertGreaterThan(displayRuns.count, 1)
        }
    }

    private static func makeLargeMarkdownDocument(sectionCount: Int, mermaidBlockCount: Int) -> String {
        var blocks: [String] = ["# Performance Baseline"]
        blocks.reserveCapacity(sectionCount + mermaidBlockCount + 1)

        for index in 0..<sectionCount {
            blocks.append(
                """
                ## Section \(index)

                This paragraph contains `inline code`, **bold text**, and a local [anchor](#section-\(max(0, index - 1))).

                - Item \(index).1 with escaped <angle> content
                - Item \(index).2 with repeated text for preview rendering throughput

                | Key | Value |
                | --- | --- |
                | section | \(index) |
                | state | active |
                """
            )

            if index < mermaidBlockCount {
                blocks.append(
                    """
                    ```mermaid
                    flowchart LR
                        Source\(index)[Source \(index)] --> Parse\(index){Parse}
                        Parse\(index) --> Preview\(index)[Preview]
                    ```
                    """
                )
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func makeTerminalOutputChunks(chunkCount: Int, linesPerChunk: Int) -> [String] {
        (0..<chunkCount).map { chunkIndex in
            (0..<linesPerChunk).map { lineIndex in
                let absoluteLineIndex = chunkIndex * linesPerChunk + lineIndex
                return "\u{1B}[32mline \(absoluteLineIndex)\u{1B}[0m output payload for scrollback stress\n"
            }.joined()
        }
    }
}
