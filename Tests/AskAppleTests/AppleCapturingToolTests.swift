internal import FoundationModels
internal import Testing

@testable import AskApple

/// The tool the framework calls does not run anything: it hands the call back to ask's loop, which runs it under the sandbox.
@Suite("A captured tool call goes back to the loop and ends the response")
struct AppleCapturingToolTests {
    private func tool(_ capture: AppleCapture, name: String = "read") throws -> AppleCapturingTool {
        let schema = try #require(
            AppleToolSchema.schema(
                named: name, description: "d",
                inputSchema: Array(#"{"type":"object","properties":{"path":{"type":"string"}}}"#.utf8)))
        return AppleCapturingTool(name: name, description: "d", parameters: schema, capture: capture)
    }

    @Test func `a call is recorded with its arguments as JSON, then the response is ended`() async throws {
        let capture = AppleCapture()
        let tool = try tool(capture)
        await #expect(throws: AppleCapturingTool.Handoff.self) {
            try await tool.call(arguments: GeneratedContent(json: #"{"path":"notes.txt"}"#))
        }
        let call = try #require(capture.call)
        #expect(call.name == "read" && call.arguments.contains("notes.txt") && call.id.hasPrefix("apple_"))
    }

    @Test func `only the first call is kept, so a response that makes several is answered one at a time`() async throws
    {
        let capture = AppleCapture()
        let first = try tool(capture, name: "first")
        let second = try tool(capture, name: "second")
        _ = try? await first.call(arguments: GeneratedContent(json: #"{"path":"a"}"#))
        _ = try? await second.call(arguments: GeneratedContent(json: #"{"path":"b"}"#))
        #expect(capture.call?.name == "first")
    }

    @Test func `no call, nothing captured`() { #expect(AppleCapture().call == nil) }
}
