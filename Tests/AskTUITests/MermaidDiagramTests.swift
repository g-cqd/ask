internal import Testing

@testable import AskTUI

/// A fenced block in the `mermaid` language is drawn as the diagram once its fence closes (roadmap 0198), and stays the code block when it is still open, is not a diagram
/// the engine draws, or does not fit the width.
@Suite("A closed mermaid fence is drawn as a diagram")
struct MermaidDiagramTests {
    static let diagram = "flowchart TD\n  A[Start] --> B{Ready?}\n  B -->|yes| C[Go]\n  B -->|no| D[Wait]"

    private func rows(_ text: String, columns: Int = 80) -> [String] {
        var transcript = MarkdownRowCacheTests.transcript(folded: false)
        transcript.addAssistantText(text)
        return ScreenComposer.lines(in: transcript, at: 0, columns: columns).map(\.text)
    }

    @Test func `a closed fence is a diagram, with no fence line left`() {
        let lines = rows("Here is the flow:\n\n```mermaid\n\(Self.diagram)\n```\n\nDone.")
        let text = lines.joined(separator: "\n")
        #expect(text.contains("┌") && text.contains("Start") && text.contains("Ready?") && text.contains("yes"))
        #expect(!text.contains("```") && !text.contains("flowchart"))
        #expect(text.contains("Here is the flow:") && text.contains("Done."))
    }

    @Test func `an open fence stays code while it streams, and becomes the diagram when it closes`() {
        let open = rows("```mermaid\n\(Self.diagram)\n").joined(separator: "\n")
        #expect(open.contains("flowchart TD") && !open.contains("┌"))
        let closed = rows("```mermaid\n\(Self.diagram)\n```\n").joined(separator: "\n")
        #expect(closed.contains("┌") && !closed.contains("flowchart"))
    }

    @Test func `a warm transcript draws what a fresh one draws as the fence closes`() {
        var warm = MarkdownRowCacheTests.transcript(folded: false)
        let text = "before\n\n```mermaid\n\(Self.diagram)\n```\n\nafter\n"
        var shown = ""
        for piece in stride(from: 0, to: text.count, by: 7) {
            let delta = String(text.dropFirst(piece).prefix(7))
            shown += delta
            warm.addAssistantText(delta)
            #expect(
                ScreenComposer.lines(in: warm, at: 0, columns: 60).map(\.text) == rows(shown, columns: 60),
                "after \(shown.count) characters"
            )
        }
    }

    @Test func `other languages, and a fence with no language, are unchanged`() {
        let swift = rows("```swift\nlet a = 1\n```").joined(separator: "\n")
        #expect(swift.contains("let a = 1") && !swift.contains("┌"))
        #expect(rows("```\nflowchart TD\nA-->B\n```").joined(separator: "\n").contains("flowchart TD"))
    }

    @Test func `a sequence diagram is drawn`() {
        let text = rows("```mermaid\nsequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi\n```")
            .joined(separator: "\n")
        #expect(text.contains("Alice") && text.contains("Hello") && text.contains("▶"))
    }

    @Test func `a diagram that does not fit the width is shown as the code it is`() {
        let text = rows(
            "```mermaid\nflowchart LR\n  A[A very long label indeed] --> B[Another very long label]\n```",
            columns: 8
        )
        .joined(separator: "\n")
        #expect(text.contains("flowch") && !text.contains("┌"), "too narrow for any layout: the code is shown, wrapped")
    }

    @Test func `source the engine cannot read is shown as code`() {
        #expect(
            rows("```mermaid\ngantt\n  title A plan\n```").joined(separator: "\n").contains("gantt")
        )
        #expect(rows("```mermaid\nnot a diagram at all\n```").joined(separator: "\n").contains("not a diagram"))
    }

    @Test func `escape sequences in a label never reach the screen`() {
        let hostile = "```mermaid\nflowchart TD\n  A[\"\u{1B}[2J\u{1B}]0;pwned\u{07}x\"] --> B[\"\u{202E}evil\"]\n```"
        for line in rows(hostile) {
            #expect(
                line.unicodeScalars.allSatisfy {
                    $0.value >= 0x20 && $0.value != 0x7F && !(0x202A ... 0x202E).contains($0.value)
                },
                "\(line.debugDescription)"
            )
        }
    }

    @Test(arguments: [24, 40, 80, 120])
    func `no row is wider than the transcript`(columns: Int) {
        for line in rows("```mermaid\n\(Self.diagram)\n```", columns: columns) {
            #expect(line.count <= columns, "\(line.debugDescription)")
        }
    }

    @Test func `state, class, entity and pie diagrams are drawn too`() {
        let state = rows("```mermaid\nstateDiagram-v2\n  [*] --> Idle\n  Idle --> Busy : go\n```")
            .joined(separator: "\n")
        #expect(
            state.contains("Idle") && state.contains("Busy") && state.contains("go") && !state.contains("stateDiagram")
        )
        let classes = rows("```mermaid\nclassDiagram\n  Animal <|-- Duck\n  Animal : +int age\n```")
            .joined(separator: "\n")
        #expect(classes.contains("Animal") && classes.contains("+int age") && classes.contains("┌"))
        let entities = rows("```mermaid\nerDiagram\n  CUSTOMER ||--o{ ORDER : places\n```").joined(separator: "\n")
        #expect(entities.contains("CUSTOMER") && entities.contains("places"))
        let pie = rows("```mermaid\npie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 1\n```").joined(separator: "\n")
        #expect(pie.contains("Dogs") && pie.contains("75.0%") && pie.contains("█"))
    }
}
