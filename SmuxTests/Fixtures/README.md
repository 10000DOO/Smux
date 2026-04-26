# Mermaid Preview Fixtures

## P0-4 Offline Render Scope

P0-4 verifies the preview pipeline without asking WKWebView to render Mermaid output over the network.

Supported behavior:

- `mermaid` and `mmd` fenced code blocks are extracted into `MermaidBlockState` values.
- The sanitized Markdown output contains placeholders instead of duplicated Mermaid source code HTML.
- The representative fixture covers `flowchart`, `sequenceDiagram`, `stateDiagram-v2`, `gantt`, `classDiagram`, and `erDiagram`.
- Offline WebView HTML generation uses the app-bundled `mermaid.min.js` source and does not emit external script references.

Unsupported behavior:

- Empty Mermaid source is rejected by render input preparation.
- Unknown diagram declarations are rejected as unsupported Mermaid syntax.
- Missing `mermaid.min.js` or fallback `mermaid.js` app resources fail offline render preparation.
- These fixtures do not prove that WKWebView produced SVG pixels; that belongs to a later integration/UI render check.
