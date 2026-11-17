internal import AskAI
internal import AskAgentCore
internal import Foundation
internal import Testing

@testable import AskTools

/// What the model is told about each tool's arguments, byte for byte: the schema, with what each argument says of itself
/// (ADR-0157), and the `sandbox` argument a call may narrow itself with (roadmap 0019).
///
/// A provider caches the tool list as part of the prompt, so a schema that moved even by a space would cost every user a
/// cache miss: a change here is meant, and made once for all the tools together.
@Suite("The tools' schemas are exactly what is written here")
struct ToolDefinitionTests {
    private func schema(_ tool: any Tool) -> String {
        String(decoding: tool.definition.inputSchema.bytes, as: UTF8.self)
    }

    @Test func `read`() {
        #expect(
            schema(ReadTool())
                == #"{"type":"object","properties":{"path":{"type":"string","description":"The file: absolute, or relative to the working directory."},"offset":{"type":"integer","minimum":1,"description":"Text: the first line to return, counting from 1."},"limit":{"type":"integer","minimum":1,"description":"Text: how many lines to return."},"pages":{"type":"string","description":"PDF: the pages to read, such as \"1-3,7\"."},"at":{"type":"array","items":{"type":"number","minimum":0},"description":"Video: the seconds at which to take frames, exactly."},"every":{"type":"number","exclusiveMinimum":0,"description":"Video: a frame every this many seconds."},"start":{"type":"number","minimum":0,"description":"Video: where the frames begin, in seconds."},"end":{"type":"number","minimum":0,"description":"Video: where the frames end, in seconds."},"max_images":{"type":"integer","minimum":1,"maximum":20,"description":"The most pictures one call returns: 8 unless given. Video: that many frames, 4 unless given, spread evenly from start to end."},"render":{"type":"boolean","description":"PDF: every page as a picture, also a page that has text."},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}},"required":["path"]}"#
        )
    }

    @Test func `write`() {
        #expect(
            schema(WriteTool())
                == #"{"type":"object","properties":{"path":{"type":"string","description":"The file: absolute, or relative to the working directory."},"content":{"type":"string","description":"The whole file. Not with old_text."},"old_text":{"type":"string","minLength":1,"description":"The exact text to replace, enough of it to match once."},"new_text":{"type":"string","description":"What replaces old_text."},"replace_all":{"type":"boolean","description":"Replace every match."},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}}}}},"required":["path"]}"#
        )
    }

    @Test func `bash`() {
        #expect(
            schema(BashTool())
                == #"{"type":"object","properties":{"command":{"type":"string","description":"What to run."},"timeout_seconds":{"type":"integer","minimum":1,"maximum":600,"description":"Stop the command after this long: 120 unless given."},"yield_seconds":{"type":"integer","minimum":1,"maximum":600,"description":"Return after this long; the command goes on as a job."},"wait_for_output":{"type":"string","minLength":1,"description":"Return once it prints this text; it goes on as a job."},"wait_for_port":{"type":"integer","minimum":1,"maximum":65535,"description":"Return once this local port accepts connections; it goes on as a job."},"wait_for_file":{"type":"string","minLength":1,"description":"Return once this file exists; it goes on as a job."},"shell":{"type":"string","description":"Another shell for this command, by absolute path."},"sandbox":{"type":"object","description":"Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. write, read: paths relative to the working directory. session: keep holds it for every later call (stop jobs first); reset asks the person to undo that.","properties":{"network":{"type":"string","enum":["none","localhost","provider","any"]},"write":{"type":"array","items":{"type":"string"}},"read":{"type":"array","items":{"type":"string"}},"session":{"type":"string","enum":["keep","reset"]}}}},"required":["command"]}"#
        )
    }
}
