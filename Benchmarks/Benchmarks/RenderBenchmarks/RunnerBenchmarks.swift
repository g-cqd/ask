import AskTUI
import Benchmark
import TerminalKitRender

/// A keystroke frame (layout plus diff), with no runners, five, or fifty: the strip is open, bounded to five rows. The fixture is the same for the
/// old above-status list and the below-input strip, so the same harness measures both.
func registerRunnerBenchmarks() {
    for count in [0, 5, 50] {
        Benchmark(
            "runners/\(count) keystroke",
            configuration: .init(metrics: [.wallClock], maxDuration: .seconds(2), maxIterations: 2_000)
        ) { benchmark in
            var state = ScreenState(label: "m")
            for i in 0 ..< 200 { state.transcript.addNotice("line \(i)", isError: false) }
            state.runners = (0 ..< count).map { RunnerInfo(name: "job-\($0)", detail: "sleep \($0)") }
            state.runnersOpen = true
            var composer = ScreenComposer()
            var front = ScreenBuffer(columns: 120, rows: 40)
            var back = ScreenBuffer(columns: 120, rows: 40)
            _ = composer.compose(state, into: &front)
            benchmark.startMeasurement()
            for iteration in benchmark.scaledIterations {
                _ = state.editor.apply(.init(keyCode: iteration % 2 == 0 ? 0x78 : 0x7F))
                _ = composer.compose(state, into: &back)
                blackHole(DiffRenderer.render(front: front, back: back))
                front = back
                back.dirty.clear()
            }
        }
    }
}
