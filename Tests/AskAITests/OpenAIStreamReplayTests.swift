internal import Foundation
internal import Testing

@testable import AskAI

/// The decoder reproduces what three real servers sent, recorded byte for byte.
///
/// llama.cpp, MLX and Ollama all serve `/v1/chat/completions` and all differ: the reasoning field is
/// `reasoning_content` or `reasoning`, tool arguments arrive in fragments or whole, usage comes in a chunk, in a
/// `chat.completion` object or in a chunk with no choices, and stray `""` or `"\n\n"` content appears. The
/// recordings (`Tests/Fixtures/OpenAICompatible`, captured from Ornith-1.5-9B on each server) are what the adapter
/// is written against, so a test that passes here passes on what servers actually send.
@Suite("Recorded streams from llama.cpp, MLX and Ollama decode to the same response")
struct OpenAIStreamReplayTests {
    static let servers = ["llamacpp", "mlx", "ollama"]

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/OpenAICompatible")

    /// The recorded bytes, decoded and assembled, delivered in pieces of `chunk` bytes.
    static func replay(_ name: String, chunk: Int = .max) throws -> AssembledResponse {
        let bytes = Array(try Data(contentsOf: fixtures.appending(path: "\(name).sse")))
        var framer = SSEDecoder()
        var decoder = OpenAIStreamDecoder()
        var assembler = ResponseAssembler()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        var offset = 0
        while offset < bytes.count {
            let end = Swift.min(bytes.count, offset + Swift.max(1, chunk))
            try framer.feed(bytes[offset ..< end].span, into: &frames)
            for frame in frames { try decoder.decode(frame, into: &events) }
            frames.removeAll()
            offset = end
        }
        try decoder.finish(into: &events)
        for event in events { try assembler.apply(event) }
        return try assembler.finish()
    }

    private static func toolCalls(_ response: AssembledResponse) -> [(name: String, input: String)] {
        response.blocks.compactMap {
            guard case .toolCall(_, let name, let input) = $0 else { return nil }
            return (name, String(decoding: input.bytes, as: UTF8.self))
        }
    }

    private static func text(_ response: AssembledResponse) -> String {
        response.blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
    }

    @Test(arguments: OpenAIStreamReplayTests.servers)
    func `a tool call decodes to one tool block with valid input and stops for tool use`(server: String) throws {
        let response = try Self.replay("\(server)-tool-call")
        let calls = Self.toolCalls(response)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read")
        let input = try #require(calls.first?.input)
        let path = try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: String]
        #expect(path?["path"] == "notes/todo.txt")
        #expect(response.stopReason == .toolUse)
        // No whitespace-only text block survives: a provider such as Anthropic rejects one if the session moves.
        #expect(
            !response.blocks.contains {
                if case .text(let text) = $0 { text.allSatisfy(\.isWhitespace) } else { false }
            })
    }

    @Test(arguments: OpenAIStreamReplayTests.servers)
    func `reasoning arrives as a thinking block with no signature, ahead of the call`(server: String) throws {
        let response = try Self.replay("\(server)-tool-call")
        guard case .thinking(let text, let signature) = response.blocks.first else {
            Issue.record("the first block is not thinking: \(response.blocks)")
            return
        }
        #expect(!text.isEmpty)
        #expect(signature.isEmpty)
    }

    @Test(arguments: OpenAIStreamReplayTests.servers)
    func `text decodes exactly, multi-byte characters included, and stops at the end of the turn`(server: String) throws
    {
        let response = try Self.replay("\(server)-text")
        #expect(Self.text(response).trimmingCharacters(in: .whitespacesAndNewlines) == "héllo wörld ✓")
        #expect(response.stopReason == .endTurn)
        #expect(Self.toolCalls(response).isEmpty)
    }

    @Test(arguments: OpenAIStreamReplayTests.servers)
    func `usage is reported, with cached prompt tokens apart from new ones`(server: String) throws {
        let usage = try Self.replay("\(server)-tool-call").usage
        let input = try #require(usage.input)
        let cached = usage.cacheRead ?? 0
        #expect(input >= 0 && cached >= 0)
        #expect(input + cached > 0)
        #expect((usage.output ?? 0) > 0)
    }

    @Test(arguments: OpenAIStreamReplayTests.servers)
    func `the same bytes cut into seven-byte pieces decode to the same response`(server: String) throws {
        for kind in ["tool-call", "text"] {
            #expect(try Self.replay("\(server)-\(kind)", chunk: 7) == Self.replay("\(server)-\(kind)"))
        }
    }

    @Test(arguments: OpenAIStreamReplayTests.servers)
    func `the response carries the server's id and model`(server: String) throws {
        let response = try Self.replay("\(server)-text")
        #expect(!response.id.isEmpty)
        #expect(!response.model.isEmpty)
    }
}
