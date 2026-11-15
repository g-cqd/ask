import AemiJSON
import AemiJSONRPC
import Testing

@testable import AskACP

/// What a prompt's content blocks say (ACP v1, Content): text and resource links, which every agent takes.
@Suite("A prompt's text is its text blocks and its links, in order; other blocks are refused")
struct ACPPromptTests {
    private func text(_ blocks: String) throws -> Result<String, JSONRPCError> {
        ACPPrompt.text(of: try AemiJSON.parse(Array(#"{"prompt":\#(blocks)}"#.utf8)).root)
    }

    @Test func `text blocks are joined as the client cut them`() throws {
        #expect(
            try text(#"[{"type":"text","text":"explain "},{"type":"text","text":"this"}]"#) == .success("explain this")
        )
    }

    @Test func `a link to a file is its path, and any other its address, where the client put it`() throws {
        let blocks =
            #"[{"type":"text","text":"read "},{"type":"resource_link","uri":"file:///work/a b.swift","name":"a b.swift"},"#
            + #"{"type":"text","text":" and "},{"type":"resource_link","uri":"https://example.com/x","name":"x"}]"#
        #expect(try text(blocks) == .success("read /work/a b.swift and https://example.com/x"))
    }

    @Test(arguments: [
        (
            #"[{"type":"image","mimeType":"image/png","data":"AAAA"}]"#,
            "ask takes text and resource_link blocks, not image"
        ),
        (
            #"[{"type":"resource","resource":{"uri":"file:///a","text":"x"}}]"#,
            "ask takes text and resource_link blocks, not resource"
        ),
        (#"[{"text":"x"}]"#, "ask takes text and resource_link blocks, not one with no type"),
        (#"[{"type":"text"}]"#, "a text block has no text"),
        (#"[{"type":"resource_link"}]"#, "a resource_link block has no uri"),
        ("[]", "the prompt says nothing"), (#"[{"type":"text","text":""}]"#, "the prompt says nothing"),
        (#""hello""#, "prompt is missing, or not a list")
    ])
    func `what ask does not take is refused, and says what`(blocks: String, reason: String) throws {
        #expect(try text(blocks) == .failure(JSONRPCError(code: -32602, message: "Invalid params: " + reason)))
    }

    @Test func `no prompt at all is refused`() {
        #expect(
            ACPPrompt.text(of: nil)
                == .failure(JSONRPCError(code: -32602, message: "Invalid params: prompt is missing, or not a list"))
        )
    }
}
