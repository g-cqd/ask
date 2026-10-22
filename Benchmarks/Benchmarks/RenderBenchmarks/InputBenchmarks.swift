import AskTUI
import Benchmark
import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender
import TerminalKitText

func registerInputBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal], maxDuration: .seconds(1), maxIterations: 1_000)
    let text = (0 ..< 100).map { _ in String(repeating: "word ", count: 12) }.joined(separator: "\n")
    let count = text.count
    let old = LegacyPromptLayout.rows(text, cursorOffset: count, columns: 80)
    let layout = InputLayout(text, columns: 80, firstRowIndent: 5)
    let lines = layout.rows.enumerated().map { ($0.offset == 0 ? "ask> " : "") + $0.element }
    precondition(lines == old.lines && layout.position(at: count) == .init(row: old.row, column: old.column))

    Benchmark("input/cold legacy row builder, 100 lines", configuration: configuration) { benchmark in
        benchmark.startMeasurement()
        blackHole(LegacyPromptLayout.rows(text, cursorOffset: count, columns: 80))
        benchmark.stopMeasurement()
    }
    Benchmark("input/cold shared map builder, 100 lines", configuration: configuration) { benchmark in
        benchmark.startMeasurement()
        blackHole(InputLayout(text, columns: 80, firstRowIndent: 5))
        benchmark.stopMeasurement()
    }
    Benchmark("input/cached composer, 100 lines", configuration: configuration) { benchmark in
        var state = ScreenState(label: "m")
        state.editor.paste(text)
        var composer = ScreenComposer()
        var buffer = ScreenBuffer(columns: 80, rows: 24)
        _ = composer.compose(state, into: &buffer)
        buffer.dirty.clear()
        benchmark.startMeasurement()
        blackHole(composer.compose(state, into: &buffer))
        benchmark.stopMeasurement()
    }
    for (name, columns) in [("hard", Optional<Int>.none), ("wrapped", 80)] {
        Benchmark("input/Up \(name), 100 lines", configuration: configuration) { benchmark in
            var editor = PromptEditor()
            editor.paste(text)
            let up = KeyEvent(keyCode: Key.up.rawValue)
            for _ in 0 ..< 50 { _ = editor.apply(up, columns: columns, firstRowIndent: 5) }
            benchmark.startMeasurement()
            blackHole(editor.apply(up, columns: columns, firstRowIndent: 5))
            benchmark.stopMeasurement()
        }
    }
}
