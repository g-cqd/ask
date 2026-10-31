internal import AskAI
internal import AskAgentCore
internal import Foundation
internal import Testing

@testable import AskTools

/// What the model is told about each tool, byte for byte: the schemas as they were hand-written, plus the `sandbox`
/// argument a call may narrow itself with (roadmap 0019).
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
                == #"{"type":"object","properties":{"path":{"type":"string"},"offset":{"type":"integer","minimum":1},"limit":{"type":"integer","minimum":1},"pages":{"type":"string"},"at":{"type":"array","items":{"type":"number","minimum":0}},"count":{"type":"integer","minimum":1,"maximum":20},"every":{"type":"number","exclusiveMinimum":0},"start":{"type":"number","minimum":0},"end":{"type":"number","minimum":0},"max_images":{"type":"integer","minimum":1,"maximum":20},"render":{"type":"boolean"},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}},"required":["path"]}"#
        )
    }

    @Test func `write`() {
        #expect(
            schema(WriteTool())
                == #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"},"old_text":{"type":"string","minLength":1},"new_text":{"type":"string"},"replace_all":{"type":"boolean"},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}},"required":["path"]}"#
        )
    }

    @Test func `edit`() {
        #expect(
            schema(EditTool())
                == #"{"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string","minLength":1},"new_text":{"type":"string"},"replace_all":{"type":"boolean"},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}},"required":["path","old_text","new_text"]}"#
        )
    }

    @Test func `bash`() {
        #expect(
            schema(BashTool())
                == #"{"type":"object","properties":{"command":{"type":"string"},"timeout_seconds":{"type":"integer","minimum":1,"maximum":600},"yield_seconds":{"type":"integer","minimum":1,"maximum":600},"wait_for_output":{"type":"string","minLength":1},"wait_for_port":{"type":"integer","minimum":1,"maximum":65535},"wait_for_file":{"type":"string","minLength":1},"shell":{"type":"string"},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}},"required":["command"]}"#
        )
    }
}
