import AskTUI
import Benchmark
import TerminalKitRender

/// A long reply with fenced code, against the same reply without fence markers: the cost of finding fences on every streamed delta.
func registerCodeBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], maxDuration: .seconds(1), maxIterations: 1_000)
    func reply(fenced: Bool) -> String {
        var lines: [String] = []
        for block in 0 ..< 4 {
            lines += (0 ..< 20).map { "paragraph \(block) line \($0) " + String(repeating: "word ", count: 12) }
            lines.append(fenced ? "```swift" : "--- swift")
            lines += (0 ..< 40).map { "    let value\($0) = compute(\($0)) // block \(block)" }
            lines.append(fenced ? "```" : "---")
        }
        return lines.joined(separator: "\n")
    }
    for (name, fenced) in [("with 4 long fences", true), ("without fences", false)] {
        var state = ScreenState(label: "model")
        for index in 0 ..< 50 { state.transcript.addNotice("earlier item \(index)", isError: false) }
        state.transcript.addAssistantText(reply(fenced: fenced))
        Benchmark("code/stream delta, 400-line reply \(name)", configuration: configuration) { benchmark in
            var state = state
            var buffer = ScreenBuffer(columns: 120, rows: 40)
            var composer = ScreenComposer()
            _ = composer.compose(state, into: &buffer)
            benchmark.startMeasurement()
            state.transcript.addAssistantText(" more")
            blackHole(composer.compose(state, into: &buffer))
            benchmark.stopMeasurement()
        }
    }
    var state = ScreenState(label: "model")
    for index in 0 ..< 50 { state.transcript.addNotice("earlier item \(index)", isError: false) }
    state.transcript.addAssistantText(reply(fenced: true))
    Benchmark("code/open every long block", configuration: configuration) { benchmark in
        var state = state
        var buffer = ScreenBuffer(columns: 120, rows: 40)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        benchmark.startMeasurement()
        state.transcript.setCodeFoldedByDefault(false)
        blackHole(composer.compose(state, into: &buffer))
        benchmark.stopMeasurement()
    }
    Benchmark("code/unchanged frame with folded blocks", configuration: configuration) { benchmark in
        var buffer = ScreenBuffer(columns: 120, rows: 40)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        buffer.dirty.clear()
        benchmark.startMeasurement()
        blackHole(composer.compose(state, into: &buffer))
        benchmark.stopMeasurement()
    }
}
