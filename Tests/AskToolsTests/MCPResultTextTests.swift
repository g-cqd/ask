import AskMCP
import Testing

@testable import AskTools

/// What the model reads of a tool's result (ADR-0099): text as it is, and a note for what a terminal agent cannot use, never the bytes.
@Suite("A tool's result is read as text, and what is not text is named, not pasted")
struct MCPResultTextTests {
    private func text(_ content: [MCPContent], structured: String? = nil) -> String {
        MCPResultText.of(
            MCPToolResult(content: content, structuredContent: structured.map { Array($0.utf8) }, isError: false))
    }

    @Test func `text blocks are joined with a blank line`() {
        #expect(text([.text("one"), .text("two")]) == "one\n\ntwo")
    }

    @Test func `an image or sound is a note with its type and size, not its bytes`() {
        let note = text([.image(mimeType: "image/png", base64: String(repeating: "A", count: 400))])
        #expect(note == "[image image/png, 300 bytes: ask cannot show it]")
        #expect(
            text([.audio(mimeType: "audio/wav", base64: "AAAA")]) == "[audio audio/wav, 3 bytes: ask cannot play it]")
        #expect(
            text([.audio(mimeType: "audio/wav", base64: "AA==")]) == "[audio audio/wav, 1 bytes: ask cannot play it]",
            "padding is not data")
    }

    @Test func `a link names its address and a resource gives its text`() {
        #expect(text([.resourceLink(uri: "file:///a", name: "a", mimeType: nil)]) == "[resource a: file:///a]")
        #expect(text([.resource(uri: "file:///b", mimeType: "text/plain", text: "body")]) == "body")
        #expect(
            text([.resource(uri: "file:///c", mimeType: "image/png", text: nil)])
                == "[resource file:///c (image/png): no text]")
    }

    @Test func `a kind this client does not know is said, with its name`() {
        #expect(text([.unknown(type: "hologram")]) == "[a hologram block that ask does not understand]")
    }

    @Test func `structured content stands in only when there is no text`() {
        #expect(text([], structured: #"{"n":1}"#) == #"{"n":1}"#)
        #expect(text([.text("said")], structured: #"{"n":1}"#) == "said")
    }

    @Test func `an empty result says so instead of returning nothing`() {
        #expect(text([]) == "(the tool returned nothing)")
        #expect(text([.text("")]) == "(the tool returned nothing)")
    }
}
