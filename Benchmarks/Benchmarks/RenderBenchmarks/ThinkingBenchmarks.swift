import AskTUI
import Benchmark
import TerminalKitRender

/// Compare the same transcript with and without reasoning, and measure a streamed delta or a fold, not a synthetic wrap alone.
func registerThinkingBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], maxDuration: .seconds(1), maxIterations: 1_000)
    var ordinary = ScreenState(label: "model")
    for index in 0 ..< 200 { ordinary.transcript.addNotice("earlier item \(index)", isError: false) }
    let reasoning = (1 ... 400).map { "reasoning line \($0) " + String(repeating: "word ", count: 10) }
        .joined(separator: "\n")
    var folded = ordinary
    folded.transcript.addThinkingText(reasoning)
    var opened = folded
    opened.transcript.toggleFold(200)

    for (name, state) in [("ordinary", ordinary), ("folded", folded), ("open", opened)] {
        Benchmark("thinking/unchanged \(name)", configuration: configuration) { benchmark in
            var buffer = ScreenBuffer(columns: 120, rows: 40)
            var composer = ScreenComposer()
            _ = composer.compose(state, into: &buffer)
            buffer.dirty.clear()
            benchmark.startMeasurement()
            blackHole(composer.compose(state, into: &buffer))
            benchmark.stopMeasurement()
        }
    }
    Benchmark("thinking/stream delta folded 400 lines", configuration: configuration) { benchmark in
        var state = folded
        var buffer = ScreenBuffer(columns: 120, rows: 40)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        benchmark.startMeasurement()
        state.transcript.addThinkingText(" more")
        blackHole(composer.compose(state, into: &buffer))
        benchmark.stopMeasurement()
    }
    Benchmark("thinking/open 400 lines", configuration: configuration) { benchmark in
        var state = folded
        var buffer = ScreenBuffer(columns: 120, rows: 40)
        var composer = ScreenComposer()
        _ = composer.compose(state, into: &buffer)
        benchmark.startMeasurement()
        state.transcript.toggleFold(200)
        blackHole(composer.compose(state, into: &buffer))
        benchmark.stopMeasurement()
    }
}
