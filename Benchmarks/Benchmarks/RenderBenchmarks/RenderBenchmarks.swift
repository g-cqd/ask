import AskTUI
import Benchmark
import TerminalKitCodecs
import TerminalKitIO
import TerminalKitInput
import TerminalKitRender
import TerminalKitStyle

// The three frames ask's screen produces most: a keystroke, a streamed line that shifts the bottom-aligned
// transcript up a row, and a full redraw. Each is layout (ScreenComposer) plus diff (DiffRenderer), the work
// between an event and the bytes written. Bytes per frame are reported once, beside the timings.
private func transcript(lines: Int, width: Int) -> ScreenState {
    var state = ScreenState(label: "claude-sonnet-5-5")
    for index in 0 ..< lines {
        state.transcript.addNotice(String(repeating: "word ", count: width / 6) + "\(index)", isError: false)
    }
    return state
}

private func frame(
    _ state: ScreenState, composer: inout ScreenComposer, front: inout ScreenBuffer, back: inout ScreenBuffer
)
    -> Int
{
    _ = composer.compose(state, into: &back)
    let bytes = DiffRenderer.render(front: front, back: back)
    front = back
    back.dirty.clear()
    return bytes.count
}

let benchmarks: @Sendable () -> Void = {
    registerThinkingBenchmarks()
    registerInputBenchmarks()
    registerCodeBenchmarks()
    registerPickerBenchmarks()
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal], maxDuration: .seconds(2), maxIterations: 2_000)
    print(
        "Cell: size \(MemoryLayout<Cell>.size) B, stride \(MemoryLayout<Cell>.stride) B; Style stride \(MemoryLayout<Style>.stride) B; Character stride \(MemoryLayout<Character>.stride) B"
    )

    for (columns, rows) in [(120, 40), (300, 80)] {
        let base = transcript(lines: 200, width: columns)
        // Report bytes per frame once.
        do {
            var composer = ScreenComposer()
            var front = ScreenBuffer(columns: columns, rows: rows)
            var back = ScreenBuffer(columns: columns, rows: rows)
            var state = base
            let full = frame(state, composer: &composer, front: &front, back: &back)
            state.editor.paste("x")
            let key = frame(state, composer: &composer, front: &front, back: &back)
            state.transcript.addNotice("a new streamed line of ordinary length", isError: false)
            let line = frame(state, composer: &composer, front: &front, back: &back)
            print("\(columns)x\(rows): full redraw \(full) B, keystroke \(key) B, one streamed line \(line) B")
        }
        Benchmark("frame/\(columns)x\(rows) keystroke") { benchmark in
            var composer = ScreenComposer()
            var front = ScreenBuffer(columns: columns, rows: rows)
            var back = ScreenBuffer(columns: columns, rows: rows)
            var state = base
            _ = frame(state, composer: &composer, front: &front, back: &back)
            benchmark.startMeasurement()
            for iteration in benchmark.scaledIterations {
                state.editor.paste(iteration % 2 == 0 ? "x" : "y")
                blackHole(frame(state, composer: &composer, front: &front, back: &back))
            }
        }
        // The cost of editing a long multi-line prompt (n = 100 lines of 60 characters): a vertical move and a
        // typed character, each of which finds line boundaries in the whole text.
        Benchmark("editor/\(columns)x\(rows) Up and Down in a 100-line prompt") { benchmark in
            var editor = PromptEditor()
            editor.paste((0 ..< 100).map { _ in String(repeating: "word ", count: 12) }.joined(separator: "\n"))
            for _ in 0 ..< 50 { _ = editor.apply(KeyEvent(keyCode: Key.up.rawValue)) }
            benchmark.startMeasurement()
            for iteration in benchmark.scaledIterations {
                let key = iteration % 2 == 0 ? Key.up : Key.down
                blackHole(editor.apply(KeyEvent(keyCode: key.rawValue)))
            }
        }
        Benchmark("editor/\(columns)x\(rows) typing a character mid-prompt in a 100-line prompt") { benchmark in
            var editor = PromptEditor()
            editor.paste((0 ..< 100).map { _ in String(repeating: "word ", count: 12) }.joined(separator: "\n"))
            for _ in 0 ..< 50 { _ = editor.apply(KeyEvent(keyCode: Key.up.rawValue)) }
            benchmark.startMeasurement()
            for iteration in benchmark.scaledIterations {
                blackHole(editor.apply(KeyEvent(keyCode: iteration % 2 == 0 ? 0x78 : 0x7F)))
            }
        }
        Benchmark("rows/\(columns)x\(rows) rewrite every row unchanged") { benchmark in
            var buffer = ScreenBuffer(columns: columns, rows: rows)
            let line = String(repeating: "word ", count: columns / 5)
            for row in 0 ..< rows { buffer.write(line, row: row, col: 0, style: .default) }
            buffer.dirty.clear()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                for row in 0 ..< rows { buffer.write(line, row: row, col: 0, style: .default) }
            }
        }
        Benchmark("split/\(columns)x\(rows) keystroke, layout only") { benchmark in
            var composer = ScreenComposer()
            var back = ScreenBuffer(columns: columns, rows: rows)
            var state = base
            _ = composer.compose(state, into: &back)
            benchmark.startMeasurement()
            for iteration in benchmark.scaledIterations {
                state.editor.paste(iteration % 2 == 0 ? "x" : "y")
                blackHole(composer.compose(state, into: &back))
                back.dirty.clear()
            }
        }
        Benchmark("split/\(columns)x\(rows) keystroke, diff only") { benchmark in
            var composer = ScreenComposer()
            var front = ScreenBuffer(columns: columns, rows: rows)
            var back = ScreenBuffer(columns: columns, rows: rows)
            var state = base
            _ = composer.compose(state, into: &front)
            state.editor.paste("x")
            _ = composer.compose(state, into: &back)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations { blackHole(DiffRenderer.render(front: front, back: back)) }
        }
        Benchmark("frame/\(columns)x\(rows) streamed line") { benchmark in
            var composer = ScreenComposer()
            var front = ScreenBuffer(columns: columns, rows: rows)
            var back = ScreenBuffer(columns: columns, rows: rows)
            var state = base
            _ = frame(state, composer: &composer, front: &front, back: &back)
            benchmark.startMeasurement()
            for iteration in benchmark.scaledIterations {
                state.transcript.addNotice("streamed line \(iteration) of ordinary length", isError: false)
                blackHole(frame(state, composer: &composer, front: &front, back: &back))
            }
        }
        Benchmark("frame/\(columns)x\(rows) full redraw") { benchmark in
            var composer = ScreenComposer()
            let state = base
            for _ in benchmark.scaledIterations {
                composer.reset()
                var back = ScreenBuffer(columns: columns, rows: rows)
                _ = composer.compose(state, into: &back)
                blackHole(DiffRenderer.renderFull(back))
            }
        }
    }
}
