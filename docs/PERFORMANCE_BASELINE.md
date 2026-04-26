# Smux Performance Baseline

Last updated: 2026-04-26

## Scope

This document records repeatable unit-level baselines for the current MVP performance pass. The PRD target surface includes:

- App cold start: 2 seconds.
- New terminal session creation: 500 ms.
- Terminal input response: p95 32 ms.
- Markdown preview refresh: 1 second.
- Mermaid sample rendering: 1 second.

The automated baseline added in this slice covers large Markdown/Mermaid preview rendering and terminal output append/scrollback behavior. App launch, PTY session creation, end-to-end input p95, and WebView Mermaid runtime timing still need an app-level harness or Instruments pass.

## Environment

| Field | Value |
| --- | --- |
| Date | 2026-04-26 |
| Machine | MacBook Pro, Apple M1 Pro |
| CPU cores | 10 physical / 10 logical |
| RAM | 32 GB |
| OS | macOS 26.4.1 (25E253) |
| SDK | macOS 26.4 |
| Scheme | `Smux` |
| Configuration | Active Xcode test configuration |
| Destination | `platform=macOS`, arm64 |

## Automated Baselines

Command:

```sh
xcodebuild -project Smux.xcodeproj -scheme Smux -destination 'platform=macOS' -derivedDataPath /tmp/SmuxDerivedData-PerformanceBaseline test -only-testing:SmuxTests/PerformanceBaselineTests -only-testing:SmuxTests/TerminalDisplayBufferTests -only-testing:SmuxTests/TerminalOutputStoreTests
```

Result bundle:

```text
/tmp/SmuxDerivedData-PerformanceBaseline/Logs/Test/Test-Smux-2026.04.26_15-52-42-+0900.xcresult
```

| Test | Fixture | Clock average | Peak physical memory average | Status |
| --- | --- | ---: | ---: | --- |
| `testLargeMarkdownPreviewRenderPerformance` | 300 Markdown sections, 24 Mermaid blocks | 32.3 ms | 32,281 kB | Pass |
| `testTerminalOutputAppendAndScrollbackPerformance` | 2,000 ANSI output lines, 50,000 char scrollback | 544.4 ms | 50,578 kB | Pass |

## Findings

- Initial terminal stress run before optimization averaged about 5.401 seconds per measured iteration.
- Root cause was `TerminalDisplayBuffer.truncateIfNeeded()` rebuilding `text` and removing one leading line/cell per loop while scrollback exceeded the maximum character count.
- The current implementation computes display character count once, removes leading lines in one batch, and removes leading cells in one batch for the final single-line overflow.
- Large Markdown preview rendering is currently well below the 1 second PRD target for the generated unit fixture.

## Remaining Measurement Gaps

- App cold start needs launch timing outside XCTest unit scope.
- New terminal session creation needs PTY-backed integration timing.
- Terminal input response p95 needs an event-to-render measurement path.
- Mermaid WebView rendering needs an offline WebView timing harness, separate from preview HTML generation.
