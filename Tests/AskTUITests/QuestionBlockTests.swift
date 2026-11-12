import Testing

@testable import AskTUI

/// While the model's questions are open, the question panel asks them; the transcript shows no block for the call (the owner, note
/// n68). Once they are answered and sent, the block shows, its details the questions and its output the answers.
@Suite("The question block shows only once the questions are answered")
struct QuestionBlockTests {
    private func transcript() -> Transcript {
        var transcript = Transcript()
        transcript.startTool(name: "question", summary: "Which scope?", id: "q1", fullInput: "Scope: Which scope?")
        return transcript
    }

    @Test func `a question still open draws nothing`() {
        #expect(ScreenComposer.lines(in: transcript(), at: 0, columns: 100).isEmpty)
    }

    @Test func `once answered, the block shows its header, and opened its questions then the answers, no JSON`() {
        var transcript = transcript()
        transcript.setToolsFoldedByDefault(false)
        transcript.finishTool(.succeeded, output: #"Scope: chose "Only the parser""#, id: "q1")
        let text = ScreenComposer.lines(in: transcript, at: 0, columns: 100).map(\.text).joined(separator: "\n")
        #expect(text.contains("Which scope?"))
        #expect(text.contains("Scope: Which scope?"))
        #expect(text.contains("Only the parser"))
        #expect(!text.contains("{"))
    }

    @Test func `another tool still running draws its block`() {
        var transcript = Transcript()
        transcript.startTool(name: "bash", summary: "ls", id: "b1")
        #expect(!ScreenComposer.lines(in: transcript, at: 0, columns: 100).isEmpty)
    }
}
