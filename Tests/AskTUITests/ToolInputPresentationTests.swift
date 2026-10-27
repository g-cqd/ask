import TerminalKitText
import Testing

@testable import AskTUI

@Suite("Unfolded tool input is complete, independently folded and copyable")
struct ToolInputPresentationTests {
    private func transcript(_ input: String, output: String = "RESULT") -> Transcript {
        var result = Transcript()
        result.startTool(name: "shell", summary: "command · timeout 60s", id: "call", fullInput: input)
        result.finishTool(.succeeded, output: output, id: "call")
        result.setToolsFoldedByDefault(false)
        return result
    }

    private func heredoc(_ count: Int, opening: String = "cat << 'EOF' > test.py", closing: String = "EOF") -> String {
        ([opening] + (0 ..< count).map { "payload\($0)" } + [closing, "echo after"]).joined(separator: "\n")
    }

    @Test func `long multiline input appears above output with exact copy sources`() throws {
        let input = String(repeating: "command ", count: 40) + "\n界é tail"
        let transcript = transcript(input)
        let text = transcript.contentText(at: 0)
        #expect(text.contains(input + "\nRESULT"))
        for width in [1, 12, 30, 80] {
            let rows = ScreenComposer.lines(in: transcript, at: 0, columns: width)
            let hard = TranscriptContent.hardLines(of: text)
            for source in rows.compactMap(\.source) {
                #expect(hard.indices.contains(source.line))
                let line = try #require(hard.indices.contains(source.line) ? hard[source.line] : nil)
                #expect(String(line.dropFirst(source.offset).prefix(source.text.count)) == source.text)
            }
            #expect(rows.allSatisfy { UnicodeWidth.displayWidth(of: $0.text) <= Swift.max(2, width) })
        }
    }

    @Test func `input remains foldable and visible even with no stdout`() {
        var transcript = transcript("touch made.txt", output: "")
        #expect(transcript.isFoldable(0))
        #expect(transcript.contentText(at: 0).contains("touch made.txt"))
        transcript.toggleFold(0)
        #expect(!transcript.contentText(at: 0).contains("touch made.txt"))
        transcript.toggleFold(0)
        #expect(transcript.contentText(at: 0).contains("touch made.txt"))
    }

    @Test(arguments: [39, 40, 41])
    func `heredoc folding begins strictly above forty payload lines`(_ count: Int) throws {
        var transcript = transcript(heredoc(count))
        let text = transcript.contentText(at: 0)
        #expect(text.contains("payload0") && text.contains("EOF\necho after\nRESULT"))
        if count <= 40 {
            #expect(text.contains("payload\(count - 1)") && !text.contains("embedded heredoc"))
        } else {
            #expect(text.contains("payload19") && !text.contains("payload20\n"))
            #expect(text.contains("21 lines embedded heredoc"))
            let lines = TranscriptContent.hardLines(of: text)
            let line = try #require(lines.firstIndex { $0.contains("embedded heredoc") })
            let fence = try #require(transcript.codeFence(toggledByLine: line, at: 0))
            transcript.toggleCodeFold(fence, at: 0)
            #expect(transcript.contentText(at: 0).contains(heredoc(count)))
        }
    }

    @Test func `quoted redirections comments here strings and unterminated payloads never hide text`() {
        for input in [
            heredoc(45, opening: "echo '<<EOF'"), heredoc(45, opening: "# cat <<EOF"),
            heredoc(45, opening: "cat <<<EOF"), heredoc(45, closing: "NOT_EOF")
        ] {
            #expect(transcript(input).contentText(at: 0).contains(input))
        }
    }

    @Test(arguments: ["cat <<EOF", "cat <<\"EOF\"", "cat <<-EOF", "cat > test.py << 'EOF'"])
    func `common literal delimiter forms share the same fold boundary`(_ opening: String) {
        let closing = opening.contains("<<-") ? "\tEOF" : "EOF"
        let text = transcript(heredoc(45, opening: opening, closing: closing)).contentText(at: 0)
        #expect(text.contains("25 lines embedded heredoc") && text.contains(closing + "\necho after"))
    }

    @Test func `clicking an embedded fold opens only the heredoc and input copying excludes labels`() throws {
        var rig = PointerRig(
            columns: 80, rows: 80,
            updates: [
                .toolStarted(name: "shell", summary: "cat", id: "call", fullInput: heredoc(45)),
                .toolFinished(.succeeded, output: "RESULT", id: "call")
            ])
        rig.controller.state.transcript.setToolsFoldedByDefault(false)
        rig.draw()
        let placeholder = try #require((0 ..< 80).first { rig.text(row: $0).contains("embedded heredoc") })
        rig.click(row: placeholder, col: 2)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect(rig.controller.state.transcript.contentText(at: 0).contains("payload44"))
        let first = try #require((0 ..< 80).first { rig.text(row: $0) == "payload0" })
        #expect(rig.drag(from: (first, 0), to: (first + 1, 8)) == [.copy("payload0\npayload1")])
        let opener = try #require((0 ..< 80).first { rig.text(row: $0).hasPrefix("cat <<") })
        rig.click(row: opener, col: 2)
        #expect(!rig.controller.state.transcript.isFolded(0))
        #expect(!rig.controller.state.transcript.contentText(at: 0).contains("payload44"))
    }

    @Test func `multiple heredocs keep stable independent ordinals and unterminated input stays literal`() throws {
        let input = heredoc(2) + "\n" + heredoc(45)
        var transcript = transcript(input)
        let lines = TranscriptContent.hardLines(of: transcript.contentText(at: 0))
        let marker = try #require(lines.firstIndex { $0.contains("embedded heredoc") })
        let ordinal = try #require(transcript.codeFence(toggledByLine: marker, at: 0))
        #expect(ordinal == 1)
        transcript.toggleCodeFold(ordinal, at: 0)
        #expect(transcript.contentText(at: 0).contains(input))
        let unterminated = String(repeating: "cat <<EOF\n", count: 1000)
        #expect(self.transcript(unterminated).contentText(at: 0).contains(unterminated))
    }

    @Test func `control G expansion and refolding preserve the whole tool fold choice`() {
        var transcript = transcript(heredoc(45))
        transcript.setCodeFoldedByDefault(false)
        #expect(transcript.contentText(at: 0).contains("payload44"))
        #expect(!transcript.isFolded(0))
        transcript.setCodeFoldedByDefault(true)
        #expect(!transcript.contentText(at: 0).contains("payload44"))
        #expect(!transcript.isFolded(0))
    }

    @Test func `completion and background output retain the originating input by invocation ID`() {
        var transcript = Transcript()
        transcript.startTool(name: "shell", summary: "server", id: "first", fullInput: "SERVER INPUT")
        transcript.startTool(name: "shell", summary: "other", id: "second", fullInput: "OTHER INPUT")
        transcript.finishTool(.succeeded, output: "ready", id: "first", backgroundJob: "job-1")
        let started = ContinuousClock.now
        transcript.updateJob(
            JobUpdate(
                id: "job-1", label: "abcd", output: "streamed", status: .running,
                startedAt: started, lines: 1))
        transcript.setToolsFoldedByDefault(false)
        #expect(transcript.contentText(at: 0).contains("SERVER INPUT\nstreamed"))
        #expect(transcript.contentText(at: 1).contains("OTHER INPUT"))
    }
}
