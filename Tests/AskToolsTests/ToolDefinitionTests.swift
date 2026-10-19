internal import AskAI
internal import AskAgentCore
internal import Foundation
internal import Testing

@testable import AskTools

/// What the model is told about each tool did not change when the schemas stopped being hand-written JSON.
///
/// The expected strings are the schemas as they were written by hand, byte for byte. A provider caches the tool
/// list as part of the prompt, so a schema that moved even by a space would cost every user a cache miss.
@Suite("The tools' schemas are exactly what they were")
struct ToolDefinitionTests {
    private func schema(_ tool: any Tool) -> String {
        String(decoding: tool.definition.inputSchema.bytes, as: UTF8.self)
    }

    @Test func `read`() {
        #expect(
            schema(ReadTool())
                == #"{"type":"object","properties":{"path":{"type":"string"},"offset":{"type":"integer","minimum":1},"limit":{"type":"integer","minimum":1}},"required":["path"]}"#
        )
    }

    @Test func `write`() {
        #expect(
            schema(WriteTool())
                == #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}"#
        )
    }

    @Test func `edit`() {
        #expect(
            schema(EditTool())
                == #"{"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string","minLength":1},"new_text":{"type":"string"},"replace_all":{"type":"boolean"}},"required":["path","old_text","new_text"]}"#
        )
    }

    @Test func `bash`() {
        #expect(
            schema(BashTool())
                == #"{"type":"object","properties":{"command":{"type":"string"},"timeout_seconds":{"type":"integer","minimum":1,"maximum":600}},"required":["command"]}"#
        )
    }
}
