import Foundation

nonisolated protocol MarkdownPreviewRendering {
    func render(_ markdown: String) -> MarkdownPreviewRenderResult
}

nonisolated struct MarkdownPreviewRenderResult: Hashable {
    var sanitizedMarkdown: SanitizedMarkdown
    var errors: [PreviewRenderError]
}

nonisolated struct BasicMarkdownPreviewRenderer: MarkdownPreviewRendering {
    func render(_ markdown: String) -> MarkdownPreviewRenderResult {
        var renderer = MarkdownHTMLRenderer(markdown: markdown)
        return renderer.render()
    }
}

private nonisolated struct MarkdownHTMLRenderer {
    private let lines: [String]
    private var index = 0
    private var html: [String] = []
    private var errors: [PreviewRenderError] = []

    init(markdown: String) {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.lines = normalized.components(separatedBy: "\n")
    }

    mutating func render() -> MarkdownPreviewRenderResult {
        while index < lines.count {
            if isBlank(lines[index]) {
                index += 1
            } else if let fence = codeFenceInfo(from: lines[index]) {
                renderCodeBlock(fence: fence)
            } else if isTableStart(at: index) {
                renderTable()
            } else if let heading = headingInfo(from: lines[index]) {
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
            } else if blockquoteContent(from: lines[index]) != nil {
                renderBlockquote()
            } else if listItem(from: lines[index]) != nil {
                renderList()
            } else {
                renderParagraph()
            }
        }

        return MarkdownPreviewRenderResult(
            sanitizedMarkdown: SanitizedMarkdown(html: html.joined(separator: "\n")),
            errors: errors
        )
    }

    private mutating func renderCodeBlock(fence: CodeFenceInfo) {
        let startLine = index + 1
        var codeLines: [String] = []
        var didClose = false
        index += 1

        while index < lines.count {
            if isCodeFenceClose(lines[index], marker: fence.marker) {
                didClose = true
                index += 1
                break
            }

            codeLines.append(lines[index])
            index += 1
        }

        if !didClose {
            errors.append(
                PreviewRenderError(
                    id: UUID(),
                    message: "Unclosed code fence.",
                    sourceRange: SourceRange(startLine: startLine, endLine: max(startLine, lines.count))
                )
            )
        }

        let languageClass = fence.language.map { " class=\"language-\(escapeAttribute($0))\"" } ?? ""
        html.append("<pre><code\(languageClass)>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
    }

    private mutating func renderTable() {
        let headerCells = tableCells(from: lines[index])
        index += 2

        html.append("<table>")
        html.append("<thead><tr>\(normalizedCells(headerCells, count: headerCells.count).map { "<th>\(renderInline($0))</th>" }.joined())</tr></thead>")
        html.append("<tbody>")

        while index < lines.count, !isBlank(lines[index]), lines[index].contains("|") {
            let rowCells = normalizedCells(tableCells(from: lines[index]), count: headerCells.count)
            html.append("<tr>\(rowCells.map { "<td>\(renderInline($0))</td>" }.joined())</tr>")
            index += 1
        }

        html.append("</tbody>")
        html.append("</table>")
    }

    private mutating func renderBlockquote() {
        var quoteLines: [String] = []

        while index < lines.count, let content = blockquoteContent(from: lines[index]) {
            quoteLines.append(content)
            index += 1
        }

        let body = quoteLines.map { renderInline($0) }.joined(separator: "<br>")
        html.append("<blockquote>\(body)</blockquote>")
    }

    private mutating func renderList() {
        guard let firstItem = listItem(from: lines[index]) else {
            return
        }

        let tag = firstItem.kind == .ordered ? "ol" : "ul"
        html.append("<\(tag)>")

        while index < lines.count, let item = listItem(from: lines[index]), item.kind == firstItem.kind {
            html.append("<li>\(renderInline(item.text))</li>")
            index += 1
        }

        html.append("</\(tag)>")
    }

    private mutating func renderParagraph() {
        var paragraphLines: [String] = []

        while index < lines.count, !isBlank(lines[index]), !startsBlock(at: index) {
            paragraphLines.append(lines[index].trimmingCharacters(in: .whitespaces))
            index += 1
        }

        html.append("<p>\(renderInline(paragraphLines.joined(separator: " ")))</p>")
    }

    private func startsBlock(at lineIndex: Int) -> Bool {
        codeFenceInfo(from: lines[lineIndex]) != nil
            || isTableStart(at: lineIndex)
            || headingInfo(from: lines[lineIndex]) != nil
            || blockquoteContent(from: lines[lineIndex]) != nil
            || listItem(from: lines[lineIndex]) != nil
    }

    private func isTableStart(at lineIndex: Int) -> Bool {
        guard lineIndex + 1 < lines.count else {
            return false
        }

        let headerCells = tableCells(from: lines[lineIndex])
        let separatorCells = tableCells(from: lines[lineIndex + 1])
        return headerCells.count > 1
            && separatorCells.count == headerCells.count
            && separatorCells.allSatisfy(isTableSeparatorCell)
    }

    private func tableCells(from line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)

        if row.first == "|" {
            row.removeFirst()
        }

        if row.last == "|" {
            row.removeLast()
        }

        return row
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func normalizedCells(_ cells: [String], count: Int) -> [String] {
        if cells.count >= count {
            return Array(cells.prefix(count))
        }

        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func isTableSeparatorCell(_ cell: String) -> Bool {
        var value = cell.trimmingCharacters(in: .whitespaces)

        if value.first == ":" {
            value.removeFirst()
        }

        if value.last == ":" {
            value.removeLast()
        }

        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }

    private func headingInfo(from line: String) -> HeadingInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0

        for character in trimmed {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }

        guard (1...6).contains(level) else {
            return nil
        }

        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard markerEnd < trimmed.endIndex, trimmed[markerEnd].isWhitespace else {
            return nil
        }

        let textStart = trimmed.index(after: markerEnd)
        let text = trimmed[textStart...].trimmingCharacters(in: .whitespaces)
        return HeadingInfo(level: level, text: text)
    }

    private func blockquoteContent(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == ">" else {
            return nil
        }

        var content = trimmed.dropFirst()
        if content.first == " " {
            content = content.dropFirst()
        }
        return String(content)
    }

    private func listItem(from line: String) -> MarkdownListItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return MarkdownListItem(kind: .unordered, text: String(trimmed.dropFirst(marker.count)))
        }

        let characters = Array(trimmed)
        var digitCount = 0
        while digitCount < characters.count, characters[digitCount].isNumber {
            digitCount += 1
        }

        guard digitCount > 0, digitCount + 1 < characters.count else {
            return nil
        }

        let marker = characters[digitCount]
        let separator = characters[digitCount + 1]
        guard (marker == "." || marker == ")") && separator.isWhitespace else {
            return nil
        }

        return MarkdownListItem(kind: .ordered, text: String(characters.dropFirst(digitCount + 2)))
    }

    private func codeFenceInfo(from line: String) -> CodeFenceInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker: String

        if trimmed.hasPrefix("```") {
            marker = "```"
        } else if trimmed.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }

        let info = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        let language = sanitizedLanguage(info)
        return CodeFenceInfo(marker: marker, language: language)
    }

    private func isCodeFenceClose(_ line: String, marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
    }

    private func sanitizedLanguage(_ info: String) -> String? {
        guard let firstToken = info.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }

        let allowed = firstToken.filter { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "#"
        }
        return allowed.isEmpty ? nil : String(allowed)
    }

    private func renderInline(_ text: String) -> String {
        var result = ""
        var current = text.startIndex

        while let labelStart = text[current...].firstIndex(of: "[") {
            guard let labelEnd = text[labelStart...].firstIndex(of: "]") else {
                break
            }

            let afterLabel = text.index(after: labelEnd)
            guard afterLabel < text.endIndex, text[afterLabel] == "(" else {
                result += escapeHTML(String(text[current...labelStart]))
                current = text.index(after: labelStart)
                continue
            }

            guard let urlEnd = text[afterLabel...].firstIndex(of: ")") else {
                break
            }

            result += escapeHTML(String(text[current..<labelStart]))

            let labelText = String(text[text.index(after: labelStart)..<labelEnd])
            let urlStart = text.index(after: afterLabel)
            let rawURL = String(text[urlStart..<urlEnd])

            if let safeURL = sanitizedURL(rawURL) {
                result += "<a href=\"\(escapeAttribute(safeURL))\" rel=\"noopener noreferrer\">\(escapeHTML(labelText))</a>"
            } else {
                result += escapeHTML(String(text[labelStart...urlEnd]))
            }

            current = text.index(after: urlEnd)
        }

        result += escapeHTML(String(text[current...]))
        return result
    }

    private func sanitizedURL(_ rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        if let colonIndex = lowercased.firstIndex(of: ":") {
            let scheme = lowercased[..<colonIndex]
            if !scheme.contains("/") && !scheme.contains("?") && !scheme.contains("#") {
                guard scheme == "http" || scheme == "https" || scheme == "mailto" else {
                    return nil
                }
            }
        }

        return trimmed
    }

    private func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private nonisolated enum MarkdownListKind: Equatable {
    case unordered
    case ordered
}

private nonisolated struct MarkdownListItem {
    var kind: MarkdownListKind
    var text: String
}

private nonisolated struct HeadingInfo {
    var level: Int
    var text: String
}

private nonisolated struct CodeFenceInfo {
    var marker: String
    var language: String?
}

private nonisolated func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private nonisolated func escapeAttribute(_ value: String) -> String {
    escapeHTML(value)
}
