import AppKit
import SwiftUI
import WebKit

struct PreviewWebViewRepresentable: NSViewRepresentable {
    typealias NSViewType = WKWebView

    var state: PreviewState?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = PreviewWebViewHTMLBuilder.makeHTML(state: state)

        guard context.coordinator.lastHTML != html else {
            return
        }

        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(Self.policy(for: navigationAction.navigationType, url: navigationAction.request.url))
        }

        static func policy(for navigationType: WKNavigationType, url: URL?) -> WKNavigationActionPolicy {
            guard navigationType == .linkActivated else {
                return .allow
            }

            return isInternalAnchorURL(url) ? .allow : .cancel
        }

        private static func isInternalAnchorURL(_ url: URL?) -> Bool {
            guard let url, url.fragment != nil else {
                return false
            }

            if url.scheme == nil, url.host == nil, url.path.isEmpty {
                return true
            }

            return url.scheme == "about" && url.host == nil && url.path == "blank"
        }
    }
}

nonisolated enum PreviewWebViewHTMLBuilder {
    static func makeHTML(state: PreviewState?) -> String {
        let mermaidJavaScript = state?.mermaidBlocks.isEmpty == false
            ? bundledMermaidJavaScriptSource
            : nil

        return htmlDocument(
            body: bodyHTML(state: state, rendersMermaidInBrowser: mermaidJavaScript != nil),
            zoom: state?.zoom ?? 1,
            mermaidJavaScript: mermaidJavaScript
        )
    }

    private static func bodyHTML(state: PreviewState?, rendersMermaidInBrowser: Bool) -> String {
        guard let state else {
            return emptyStateHTML(
                title: "No preview available",
                message: "Open a Markdown document to show the rendered preview."
            )
        }

        guard let sanitizedMarkdown = state.sanitizedMarkdown else {
            return unavailableStateHTML(state: state)
        }

        var body = sanitizedMarkdown.html.trimmingCharacters(in: .whitespacesAndNewlines)
        var placedBlockIDs = Set<UUID>()

        for block in state.mermaidBlocks {
            let blockHTML = mermaidBlockHTML(block, rendersInBrowser: rendersMermaidInBrowser)
            if replaceMermaidPlaceholder(blockID: block.id, in: &body, with: blockHTML) {
                placedBlockIDs.insert(block.id)
            }
        }

        if body.isEmpty {
            body = emptyStateHTML(
                title: "Nothing to preview",
                message: "The current Markdown document has no rendered content."
            )
        }

        let unplacedBlocks = state.mermaidBlocks.filter { !placedBlockIDs.contains($0.id) }
        if !unplacedBlocks.isEmpty {
            body += """

            <section class="mermaid-fallback-section" aria-label="Mermaid diagrams">
            \(unplacedBlocks.map { mermaidBlockHTML($0, rendersInBrowser: rendersMermaidInBrowser) }.joined(separator: "\n"))
            </section>
            """
        }

        if !state.errors.isEmpty {
            body = renderErrorsHTML(state.errors) + "\n" + body
        }

        return body
    }

    private static let bundledMermaidJavaScriptSource: String? = {
        try? BundledMermaidJavaScriptResourceProvider()
            .loadMermaidJavaScriptResource()
            .source
    }()

    private static func unavailableStateHTML(state: PreviewState) -> String {
        let title = state.errors.isEmpty ? "Preview unavailable" : "Preview could not be rendered"
        let message = state.errors.isEmpty
            ? "The preview has not produced sanitized content yet."
            : "Review the render details below and try again after editing the document."

        return emptyStateHTML(title: title, message: message)
            + (state.errors.isEmpty ? "" : "\n\(renderErrorsHTML(state.errors))")
    }

    private static func htmlDocument(body: String, zoom: Double, mermaidJavaScript: String?) -> String {
        let normalizedZoom = min(max(zoom.isFinite ? zoom : 1, 0.5), 3)
        let mermaidScripts = mermaidJavaScript.map { source in
            """
            <script>
            \(source)
            </script>
            <script>
            (() => {
                const blocks = Array.from(document.querySelectorAll(".mermaid-render-source"));
                if (!blocks.length || !window.mermaid) {
                    return;
                }

                window.mermaid.initialize({
                    startOnLoad: false,
                    securityLevel: "strict",
                    theme: window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default"
                });

                window.mermaid.run({ nodes: blocks }).then(() => {
                    document.querySelectorAll(".mermaid-block--rendering .mermaid-badge").forEach((badge) => {
                        badge.textContent = "Rendered";
                    });
                }).catch((error) => {
                    document.querySelectorAll(".mermaid-block--rendering").forEach((block) => {
                        block.classList.remove("mermaid-block--rendering");
                        block.classList.add("mermaid-block--failed");
                        const meta = document.createElement("p");
                        meta.className = "mermaid-meta";
                        meta.textContent = error && error.message ? error.message : "Mermaid render failed.";
                        block.querySelector(".mermaid-artifact")?.appendChild(meta);
                        block.querySelector(".mermaid-badge").textContent = "Failed";
                    });
                });
            })();
            </script>
            """
        } ?? ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
        <style>
        :root {
            color-scheme: light dark;
            --preview-zoom: \(normalizedZoom);
            --background: #f7f8fa;
            --text: #1d1d20;
            --muted: #6b7280;
            --border: #d8dde6;
            --surface: #ffffff;
            --surface-muted: #f1f4f8;
            --accent: #0f766e;
            --danger: #b42318;
            --code: #f6f8fa;
            --syntax-comment: #6b7280;
            --syntax-keyword: #8250df;
            --syntax-literal: #0550ae;
            --syntax-number: #116329;
            --syntax-property: #953800;
            --syntax-string: #0a7c72;
            --syntax-variable: #9a6700;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --background: #17191d;
                --text: #eff2f6;
                --muted: #a7b0bd;
                --border: #343a44;
                --surface: #20242b;
                --surface-muted: #292f38;
                --accent: #5eead4;
                --danger: #f97066;
                --code: #111418;
                --syntax-comment: #8b949e;
                --syntax-keyword: #d2a8ff;
                --syntax-literal: #79c0ff;
                --syntax-number: #7ee787;
                --syntax-property: #ffa657;
                --syntax-string: #a5d6ff;
                --syntax-variable: #f2cc60;
            }
        }

        html {
            background: var(--background);
        }

        body {
            box-sizing: border-box;
            max-width: 880px;
            min-height: 100vh;
            margin: 0 auto;
            padding: 32px 36px 56px;
            background: var(--background);
            color: var(--text);
            font: 15px/1.58 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            transform: scale(var(--preview-zoom));
            transform-origin: top center;
        }

        h1, h2, h3, h4, h5, h6 {
            margin: 1.35em 0 0.45em;
            line-height: 1.2;
            letter-spacing: 0;
        }

        h1:first-child, h2:first-child, h3:first-child {
            margin-top: 0;
        }

        p, ul, ol, blockquote, pre, table {
            margin: 0 0 1em;
        }

        a {
            color: var(--accent);
        }

        blockquote {
            padding: 0 0 0 14px;
            border-left: 3px solid var(--border);
            color: var(--muted);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            overflow: hidden;
        }

        th, td {
            padding: 8px 10px;
            border: 1px solid var(--border);
            text-align: left;
            vertical-align: top;
        }

        th {
            background: var(--surface-muted);
            font-weight: 600;
        }

        pre {
            overflow-x: auto;
            padding: 12px 14px;
            border: 1px solid var(--border);
            border-radius: 6px;
            background: var(--code);
        }

        code {
            font-family: "SF Mono", Menlo, Consolas, monospace;
            font-size: 0.92em;
        }

        .code-token--comment {
            color: var(--syntax-comment);
        }

        .code-token--keyword {
            color: var(--syntax-keyword);
            font-weight: 600;
        }

        .code-token--literal {
            color: var(--syntax-literal);
        }

        .code-token--number {
            color: var(--syntax-number);
        }

        .code-token--property {
            color: var(--syntax-property);
        }

        .code-token--string {
            color: var(--syntax-string);
        }

        .code-token--variable {
            color: var(--syntax-variable);
        }

        .preview-empty,
        .preview-errors,
        .mermaid-block {
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--surface);
        }

        .preview-empty {
            margin: 18vh auto 0;
            max-width: 460px;
            padding: 24px;
            text-align: center;
        }

        .preview-empty h1 {
            margin: 0 0 8px;
            font-size: 20px;
        }

        .preview-empty p,
        .preview-errors p,
        .mermaid-meta {
            color: var(--muted);
        }

        .preview-errors {
            margin: 0 0 18px;
            padding: 14px 16px;
            border-color: color-mix(in srgb, var(--danger) 40%, var(--border));
        }

        .preview-errors h2 {
            margin: 0 0 6px;
            color: var(--danger);
            font-size: 15px;
        }

        .preview-errors ul {
            margin: 8px 0 0;
            padding-left: 20px;
        }

        .mermaid-block {
            margin: 16px 0;
            overflow: hidden;
        }

        .mermaid-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            padding: 10px 12px;
            border-bottom: 1px solid var(--border);
            background: var(--surface-muted);
            font-size: 13px;
            font-weight: 600;
        }

        .mermaid-badge {
            border-radius: 999px;
            padding: 2px 8px;
            background: var(--surface);
            color: var(--muted);
            font-size: 12px;
            font-weight: 500;
        }

        .mermaid-block--failed .mermaid-badge {
            color: var(--danger);
        }

        .mermaid-artifact {
            padding: 14px;
        }

        .mermaid-artifact pre {
            margin-bottom: 0;
        }

        .mermaid-meta {
            margin: 8px 0 0;
            font-size: 13px;
        }
        </style>
        </head>
        <body>
        \(body)
        \(mermaidScripts)
        </body>
        </html>
        """
    }

    private static func replaceMermaidPlaceholder(blockID: UUID, in html: inout String, with replacement: String) -> Bool {
        let escapedID = escapeRegularExpression(blockID.uuidString)
        let pattern = #"<div\s+class="mermaid-preview-placeholder"[^>]*data-mermaid-block-id=""# + escapedID + #"\"[^>]*></div>"#

        guard let range = html.range(of: pattern, options: .regularExpression) else {
            return false
        }

        html.replaceSubrange(range, with: replacement)
        return true
    }

    private static func mermaidBlockHTML(_ block: MermaidBlockState, rendersInBrowser: Bool) -> String {
        let browserRenderPending = rendersInBrowser && block.artifact == nil && block.errorMessage == nil
        let status = browserRenderPending ? "Rendering" : escapeHTML(block.status.rawValue.capitalized)
        let artifactHTML: String

        switch block.artifact {
        case .sanitizedSVG(let svg):
            artifactHTML = svg
        case .sanitizedHTML(let html):
            artifactHTML = html
        case nil:
            if browserRenderPending {
                artifactHTML = """
                <pre class="mermaid mermaid-render-source">\(escapeHTML(block.source))</pre>
                """
            } else {
                let placeholder = block.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Diagram output is \(block.status.rawValue)."
                : block.source
                artifactHTML = "<pre><code>\(escapeHTML(placeholder))</code></pre>"
            }
        }

        let errorHTML = block.errorMessage.map {
            "<p class=\"mermaid-meta\">\(escapeHTML($0))</p>"
        } ?? ""
        let statusClass = browserRenderPending ? MermaidBlockRenderStatus.rendering.rawValue : block.status.rawValue

        return """
        <section class="mermaid-block mermaid-block--\(escapeAttribute(statusClass))" data-mermaid-block-id="\(escapeAttribute(block.id.uuidString))">
        <div class="mermaid-header">
        <span>Mermaid diagram, lines \(block.sourceRange.startLine)-\(block.sourceRange.endLine)</span>
        <span class="mermaid-badge">\(status)</span>
        </div>
        <div class="mermaid-artifact">
        \(artifactHTML)
        \(errorHTML)
        </div>
        </section>
        """
    }

    private static func renderErrorsHTML(_ errors: [PreviewRenderError]) -> String {
        let items = errors.map { error in
            let range = error.sourceRange.map { " Lines \($0.startLine)-\($0.endLine)." } ?? ""
            return "<li>\(escapeHTML(error.message + range))</li>"
        }.joined(separator: "\n")

        return """
        <section class="preview-errors" role="status" aria-label="Preview render issues">
        <h2>Preview issues</h2>
        <ul>
        \(items)
        </ul>
        </section>
        """
    }

    private static func emptyStateHTML(title: String, message: String) -> String {
        """
        <section class="preview-empty">
        <h1>\(escapeHTML(title))</h1>
        <p>\(escapeHTML(message))</p>
        </section>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value)
    }

    private static func escapeRegularExpression(_ value: String) -> String {
        NSRegularExpression.escapedPattern(for: value)
    }
}
