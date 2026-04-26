import Foundation

nonisolated enum MarkdownCodeSyntaxHighlighter {
    static func highlightedHTML(for code: String, language: String?) -> String {
        guard let language = language?.lowercased() else {
            return escapeHTML(code)
        }

        switch language {
        case "swift":
            return CStyleCodeHighlighter(keywords: swiftKeywords, literals: swiftLiterals).highlight(code)
        case "javascript", "js", "typescript", "ts":
            return CStyleCodeHighlighter(keywords: javaScriptKeywords, literals: javaScriptLiterals).highlight(code)
        case "json":
            return JSONCodeHighlighter().highlight(code)
        case "bash", "sh", "shell", "zsh":
            return ShellCodeHighlighter().highlight(code)
        case "python", "py":
            return PythonCodeHighlighter().highlight(code)
        default:
            return escapeHTML(code)
        }
    }

    private static let swiftKeywords: Set<String> = [
        "actor", "as", "associatedtype", "await", "break", "case", "catch", "class", "continue",
        "defer", "do", "else", "enum", "extension", "for", "func", "guard", "if", "import",
        "in", "init", "inout", "let", "nonisolated", "operator", "private", "protocol",
        "public", "return", "self", "static", "struct", "switch", "throw", "throws", "try",
        "typealias", "var", "where", "while"
    ]

    private static let swiftLiterals: Set<String> = [
        "false", "nil", "true"
    ]

    private static let javaScriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
        "do", "else", "export", "extends", "finally", "for", "from", "function", "if",
        "import", "in", "instanceof", "let", "new", "return", "switch", "throw", "try",
        "type", "typeof", "var", "while", "yield"
    ]

    private static let javaScriptLiterals: Set<String> = [
        "false", "null", "true", "undefined"
    ]
}

private nonisolated enum CodeTokenKind: String {
    case comment
    case keyword
    case literal
    case number
    case property
    case string
    case variable
}

private nonisolated struct CodeHTMLBuilder {
    private(set) var html: String

    init(estimatedCapacity: Int) {
        html = ""
        html.reserveCapacity(max(estimatedCapacity * 2, 16))
    }

    mutating func append(_ value: Substring, as tokenKind: CodeTokenKind? = nil) {
        append(String(value), as: tokenKind)
    }

    mutating func append(_ value: String, as tokenKind: CodeTokenKind? = nil) {
        let escaped = escapeHTML(value)

        if let tokenKind {
            html.append("<span class=\"code-token code-token--")
            html.append(tokenKind.rawValue)
            html.append("\">")
            html.append(escaped)
            html.append("</span>")
        } else {
            html.append(escaped)
        }
    }
}

private nonisolated struct CStyleCodeHighlighter {
    let keywords: Set<String>
    let literals: Set<String>

    func highlight(_ code: String) -> String {
        var builder = CodeHTMLBuilder(estimatedCapacity: code.count)
        var index = code.startIndex

        while index < code.endIndex {
            let character = code[index]

            if code.starts(with: "//", at: index) {
                let end = code.lineEnd(startingAt: index)
                builder.append(code[index..<end], as: .comment)
                index = end
            } else if character == "\"" || character == "'" {
                let end = code.quotedStringEnd(startingAt: index, delimiter: character)
                builder.append(code[index..<end], as: .string)
                index = end
            } else if character.isNumber {
                let end = code.numberEnd(startingAt: index)
                builder.append(code[index..<end], as: .number)
                index = end
            } else if character.isIdentifierStart {
                let end = code.identifierEnd(startingAt: index)
                let token = String(code[index..<end])

                if keywords.contains(token) {
                    builder.append(token, as: .keyword)
                } else if literals.contains(token) {
                    builder.append(token, as: .literal)
                } else {
                    builder.append(token)
                }
                index = end
            } else {
                let next = code.index(after: index)
                builder.append(code[index..<next])
                index = next
            }
        }

        return builder.html
    }
}

private nonisolated struct JSONCodeHighlighter {
    func highlight(_ code: String) -> String {
        var builder = CodeHTMLBuilder(estimatedCapacity: code.count)
        var index = code.startIndex

        while index < code.endIndex {
            let character = code[index]

            if character == "\"" {
                let end = code.quotedStringEnd(startingAt: index, delimiter: character)
                let tokenKind: CodeTokenKind = code.isJSONObjectKey(after: end) ? .property : .string
                builder.append(code[index..<end], as: tokenKind)
                index = end
            } else if character.isNumber || character == "-" {
                let end = code.numberEnd(startingAt: index)
                builder.append(code[index..<end], as: .number)
                index = end
            } else if character.isIdentifierStart {
                let end = code.identifierEnd(startingAt: index)
                let token = String(code[index..<end])

                if ["false", "null", "true"].contains(token) {
                    builder.append(token, as: .literal)
                } else {
                    builder.append(token)
                }
                index = end
            } else {
                let next = code.index(after: index)
                builder.append(code[index..<next])
                index = next
            }
        }

        return builder.html
    }
}

private nonisolated struct ShellCodeHighlighter {
    private let keywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if",
        "in", "then", "until", "while"
    ]

    func highlight(_ code: String) -> String {
        var builder = CodeHTMLBuilder(estimatedCapacity: code.count)
        var index = code.startIndex

        while index < code.endIndex {
            let character = code[index]

            if character == "#", code.isShellCommentStart(index) {
                let end = code.lineEnd(startingAt: index)
                builder.append(code[index..<end], as: .comment)
                index = end
            } else if character == "\"" || character == "'" {
                let end = code.quotedStringEnd(startingAt: index, delimiter: character)
                builder.append(code[index..<end], as: .string)
                index = end
            } else if character == "$" {
                let end = code.shellVariableEnd(startingAt: index)
                builder.append(code[index..<end], as: .variable)
                index = end
            } else if character.isNumber {
                let end = code.numberEnd(startingAt: index)
                builder.append(code[index..<end], as: .number)
                index = end
            } else if character.isIdentifierStart {
                let end = code.identifierEnd(startingAt: index)
                let token = String(code[index..<end])

                if keywords.contains(token) {
                    builder.append(token, as: .keyword)
                } else {
                    builder.append(token)
                }
                index = end
            } else {
                let next = code.index(after: index)
                builder.append(code[index..<next])
                index = next
            }
        }

        return builder.html
    }
}

private nonisolated struct PythonCodeHighlighter {
    private let keywords: Set<String> = [
        "and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else",
        "except", "finally", "for", "from", "if", "import", "in", "is", "lambda", "not",
        "or", "pass", "raise", "return", "try", "while", "with", "yield"
    ]

    private let literals: Set<String> = [
        "False", "None", "True"
    ]

    func highlight(_ code: String) -> String {
        var builder = CodeHTMLBuilder(estimatedCapacity: code.count)
        var index = code.startIndex

        while index < code.endIndex {
            let character = code[index]

            if character == "#" {
                let end = code.lineEnd(startingAt: index)
                builder.append(code[index..<end], as: .comment)
                index = end
            } else if character == "\"" || character == "'" {
                let end = code.quotedStringEnd(startingAt: index, delimiter: character)
                builder.append(code[index..<end], as: .string)
                index = end
            } else if character.isNumber {
                let end = code.numberEnd(startingAt: index)
                builder.append(code[index..<end], as: .number)
                index = end
            } else if character.isIdentifierStart {
                let end = code.identifierEnd(startingAt: index)
                let token = String(code[index..<end])

                if keywords.contains(token) {
                    builder.append(token, as: .keyword)
                } else if literals.contains(token) {
                    builder.append(token, as: .literal)
                } else {
                    builder.append(token)
                }
                index = end
            } else {
                let next = code.index(after: index)
                builder.append(code[index..<next])
                index = next
            }
        }

        return builder.html
    }
}

private extension String {
    nonisolated func starts(with prefix: String, at index: String.Index) -> Bool {
        self[index...].hasPrefix(prefix)
    }

    nonisolated func lineEnd(startingAt start: String.Index) -> String.Index {
        var index = start

        while index < endIndex, self[index] != "\n" {
            formIndex(after: &index)
        }

        return index
    }

    nonisolated func quotedStringEnd(startingAt start: String.Index, delimiter: Character) -> String.Index {
        var index = self.index(after: start)
        var isEscaped = false

        while index < endIndex {
            let character = self[index]

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == delimiter {
                return self.index(after: index)
            } else if character == "\n" {
                return index
            }

            formIndex(after: &index)
        }

        return endIndex
    }

    nonisolated func numberEnd(startingAt start: String.Index) -> String.Index {
        var index = start

        if index < endIndex, self[index] == "-" || self[index] == "+" {
            formIndex(after: &index)
        }

        while index < endIndex {
            let character = self[index]

            guard character.isLetter || character.isNumber || character == "." || character == "_" else {
                break
            }

            formIndex(after: &index)
        }

        return index == start ? self.index(after: start) : index
    }

    nonisolated func identifierEnd(startingAt start: String.Index) -> String.Index {
        var index = start

        while index < endIndex, self[index].isIdentifierPart {
            formIndex(after: &index)
        }

        return index
    }

    nonisolated func isJSONObjectKey(after index: String.Index) -> Bool {
        var cursor = index

        while cursor < endIndex, self[cursor] == " " || self[cursor] == "\t" {
            formIndex(after: &cursor)
        }

        return cursor < endIndex && self[cursor] == ":"
    }

    nonisolated func isShellCommentStart(_ index: String.Index) -> Bool {
        guard index > startIndex else {
            return true
        }

        return self[self.index(before: index)].isWhitespace
    }

    nonisolated func shellVariableEnd(startingAt start: String.Index) -> String.Index {
        var index = self.index(after: start)

        if index < endIndex, self[index] == "{" {
            formIndex(after: &index)

            while index < endIndex, self[index] != "}" {
                formIndex(after: &index)
            }

            if index < endIndex {
                formIndex(after: &index)
            }

            return index
        }

        while index < endIndex, self[index].isIdentifierPart {
            formIndex(after: &index)
        }

        return index
    }
}

private extension Character {
    nonisolated var isIdentifierStart: Bool {
        isLetter || self == "_"
    }

    nonisolated var isIdentifierPart: Bool {
        isLetter || isNumber || self == "_"
    }
}

private nonisolated func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
