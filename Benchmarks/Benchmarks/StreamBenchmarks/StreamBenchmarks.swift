import AskAI
import Benchmark

// A streamed text response as Anthropic sends it: 2,000 text deltas of about 24 bytes, cut into 1,500-byte
// network chunks that ignore event boundaries. Framing alone, then framing plus event decoding.
private let stream: [UInt8] = {
    var text = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"c\","
    text += "\"usage\":{\"input_tokens\":10,\"output_tokens\":1}}}\n\n"
    for index in 0 ..< 2_000 {
        text += "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,"
        text += "\"delta\":{\"type\":\"text_delta\",\"text\":\"token \(index) of the reply, \"}}\n\n"
    }
    text += "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
    return Array(text.utf8)
}()

private let chunks: [[UInt8]] = stride(from: 0, to: stream.count, by: 1_500)
    .map {
        Array(stream[$0 ..< min($0 + 1_500, stream.count)])
    }

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .throughput], maxDuration: .seconds(3), maxIterations: 1_000)

    Benchmark("stream/frame 2000 events (\(stream.count / 1024) KiB)") { benchmark in
        for _ in benchmark.scaledIterations {
            var decoder = SSEDecoder()
            var frames: [SSEEvent] = []
            for chunk in chunks { try decoder.feed(chunk.span, into: &frames) }
            blackHole(frames)
        }
    }

    // Assembly must cost the same per delta however long the block grows.
    for count in [2_000, 20_000] {
        let events: [ModelEvent] =
            [.messageStarted(id: "m", model: "c", usage: TokenUsage()), .blockStarted(index: 0, .text)]
            + (0 ..< count).map { .textDelta(index: 0, "token \($0) of the reply, ") }
            + [.blockStopped(index: 0), .messageDelta(stopReason: .endTurn, usage: TokenUsage()), .messageStopped]
        Benchmark("stream/assemble \(count) text deltas") { benchmark in
            for _ in benchmark.scaledIterations {
                var assembler = ResponseAssembler()
                for event in events { try assembler.apply(event) }
                blackHole(try assembler.finish())
            }
        }
    }

    // The whole history is re-encoded on every request, so this grows with the session.
    for turns in [50, 500] {
        let input = try! JSONObject(validating: Array(#"{"path": "Sources/AskAI/SSEDecoder.swift"}"#.utf8))
        let result = String(repeating: "let value = compute(input) // a line of a file that was read\n", count: 34)
        let messages: [ModelMessage] = (0 ..< turns)
            .flatMap { turn in
                [
                    ModelMessage(role: .user, blocks: [.text("Step \(turn): read the decoder and explain it.")]),
                    ModelMessage(
                        role: .assistant,
                        blocks: [
                            .text("Reading it."), .toolCall(id: "toolu_\(turn)", name: "read", input: input)
                        ]),
                    ModelMessage(
                        role: .user, blocks: [.toolResult(id: "toolu_\(turn)", content: result, isError: false)])
                ]
            }
        let request = ModelRequest(
            model: "claude-x", maxTokens: 8_192, systemPrompt: ["You are ask."], messages: messages, tools: [])
        Benchmark("request/encode \(turns) turns (\(AnthropicRequestEncoder.encode(request).count / 1024) KiB)") {
            benchmark in
            for _ in benchmark.scaledIterations { blackHole(AnthropicRequestEncoder.encode(request)) }
        }
    }

    Benchmark("stream/frame and decode 2000 events") { benchmark in
        for _ in benchmark.scaledIterations {
            var framer = SSEDecoder()
            let decoder = AnthropicStreamDecoder()
            var frames: [SSEEvent] = []
            var events: [ModelEvent] = []
            for chunk in chunks {
                try framer.feed(chunk.span, into: &frames)
                for frame in frames { try decoder.decode(frame, into: &events) }
                frames.removeAll(keepingCapacity: true)
            }
            blackHole(events)
        }
    }
}
