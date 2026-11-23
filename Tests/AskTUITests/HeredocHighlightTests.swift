import AemiLexers
import Foundation
import TerminalKitStyle
import Testing

@testable import AskTUI

/// Syntax highlighting for open bash call blocks and their embedded heredocs (t128): shell lines lex as `.shell`, each heredoc
/// body lexes in the language inferred from its reader (`python3`, `node`, `swift`, …), redirection target (`cat > Foo.swift`),
/// or `#!` line, fold placeholders stay dim, and all command tokens keep full brightness over the dim lead.
@Suite("Command blocks highlight shell and embedded heredoc bodies")
struct HeredocHighlightTests {
    private static let keywordStyle = CodeHighlighter.style(of: .keyword)
    private static let stringStyle = CodeHighlighter.style(of: .string)
    private static let commentStyle = CodeHighlighter.style(of: .comment)
    private static let attributeStyle = CodeHighlighter.style(of: .attribute)

    private func rows(_ command: String, columns: Int = 100, highlight: Bool = true) -> [ScreenComposer.Line] {
        var transcript = Transcript()
        transcript.highlight = highlight
        transcript.startTool(name: "bash", summary: "", id: "c1", fullInput: command, command: ToolCommand())
        transcript.finishTool(.succeeded, output: "ok", id: "c1")
        transcript.setToolsFoldedByDefault(false)
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns)
    }

    private func style(of needle: String, in line: ScreenComposer.Line) -> Style? {
        guard let range = line.text.range(of: needle) else { return nil }
        let col = line.text.distance(from: line.text.startIndex, to: range.lowerBound)
        return line.accents.first { $0.columns.contains(col) }?.style ?? line.style
    }

    @Test func `python3 heredoc highlights Python keywords, strings and comments`() throws {
        let command = """
            python3 - <<'EOF'
            # check
            def greet(name):
                return "hi"
            EOF
            """
        let map = HeredocMap(command)
        #expect(map.bodies.count == 1)
        #expect(map.bodies[0].language == .python && !map.bodies[0].expands && map.bodies[0].lines == 1 ..< 4)
        #expect(map.closers == [4])

        let lines = rows(command)
        let defRow = try #require(lines.first { $0.text.contains("def greet") })
        let retRow = try #require(lines.first { $0.text.contains("return") })
        let commentRow = try #require(lines.first { $0.text.contains("# check") })
        let closeRow = try #require(lines.first { $0.text == "EOF" })
        #expect(style(of: "def", in: defRow) == Self.keywordStyle)
        #expect(style(of: "return", in: retRow) == Self.keywordStyle)
        #expect(style(of: "\"hi\"", in: retRow) == Self.stringStyle)
        #expect(style(of: "# check", in: commentRow) == Self.commentStyle)
        #expect(style(of: "EOF", in: closeRow) == Self.keywordStyle)
    }

    @Test func `cat redirecting to a Swift file highlights the heredoc as Swift`() throws {
        let command = """
            cat > Sources/Foo.swift <<'EOF'
            struct Widget {
                let count = 42
            }
            EOF
            """
        let map = HeredocMap(command)
        #expect(map.bodies.first?.language == .swift)
        let lines = rows(command)
        let structRow = try #require(lines.first { $0.text.contains("struct Widget") })
        #expect(style(of: "struct", in: structRow) == Self.keywordStyle)
        #expect(style(of: "Widget", in: structRow) == CodeHighlighter.style(of: .type))
    }

    @Test func `multiple heredocs on one line, tab-stripped closers, shebangs and here-strings`() {
        let command = """
            cat > a.json <<A; cat <<-B > b.txt
            {"ok": true}
            A
            \t#!/usr/bin/env ruby
            \tputs "hi"
            \tB
            grep foo <<< "not a heredoc"
            cat <<<EOF
            still shell, not a heredoc
            """
        let map = HeredocMap(command)
        #expect(map.bodies.count == 2)
        #expect(map.bodies[0].language == .json && map.bodies[0].lines == 1 ..< 2 && map.bodies[0].expands)
        #expect(map.bodies[1].language == .ruby && map.bodies[1].lines == 3 ..< 5 && map.bodies[1].expands)
        #expect(map.closers == [2, 5])
    }

    @Test func `unquoted unknown heredoc highlights shell variables; quoted unknown stays plain`() throws {
        let unquoted = "cat <<EOF\nhello $USER and ${HOME}\nEOF"
        let unquotedLines = rows(unquoted)
        let body = try #require(unquotedLines.first { $0.text.contains("$USER") })
        #expect(style(of: "$USER", in: body) == Self.attributeStyle)
        #expect(style(of: "${HOME}", in: body) == Self.attributeStyle)

        let quoted = "cat <<'EOF'\nhello $USER\nEOF"
        let quotedLines = rows(quoted)
        let quotedBody = try #require(quotedLines.first { $0.text.contains("$USER") })
        #expect(quotedBody.accents.isEmpty && quotedBody.style == ScreenComposer.commandStyle)
    }

    @Test func `a folded long heredoc dims its placeholder and keeps highlighting both halves`() throws {
        let bodyLines = (0 ..< 50).map { "def f\($0)(): return \($0)" }
        let command = (["python3 - <<'EOF'"] + bodyLines + ["EOF"]).joined(separator: "\n")
        let lines = rows(command)
        let marker = try #require(lines.first { $0.text.contains("embedded heredoc") })
        #expect(style(of: "embedded", in: marker) == Style(dim: true))
        let firstDef = try #require(lines.first { $0.text.contains("def f0") })
        #expect(style(of: "def", in: firstDef) == Self.keywordStyle)
    }

    @Test func `with highlighting off, the command stays plain brightened`() throws {
        let command = "python3 - <<'EOF'\ndef f():\n    return 1\nEOF"
        let lines = rows(command, highlight: false)
        let defRow = try #require(lines.first { $0.text.contains("def f") })
        #expect(defRow.accents.isEmpty && defRow.style == ScreenComposer.commandStyle)
    }

    @Test func `a partial streamed heredoc without a closing word yet still highlights`() throws {
        let command = "python3 - <<'EOF'\nfor x in [1, 2]:\n    print(x)"
        let map = HeredocMap(command)
        #expect(map.bodies.count == 1 && map.bodies[0].language == .python && map.bodies[0].lines == 1 ..< 3)
        let lines = rows(command)
        let forRow = try #require(lines.first { $0.text.contains("for x") })
        #expect(style(of: "for", in: forRow) == Self.keywordStyle)
    }
}
