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
