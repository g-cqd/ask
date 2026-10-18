import AskTUI
import TerminalKitIO
import TerminalKitRender

// Frames through the real RenderPipeline over a mock connection: layout (ScreenComposer) then flush (dirty-range
// diff, write, adopt). Median and p99 of 2,000 frames, per window size.
func measure(_ label: String, _ frames: Int = 2_000, _ body: (Int) -> Void) {
    let clock = ContinuousClock()
    var samples: [Double] = []
    samples.reserveCapacity(frames)
    for iteration in 0 ..< frames {
        let start = clock.now
        body(iteration)
        let elapsed = clock.now - start
        samples.append(Double(elapsed.components.attoseconds) / 1e12 + Double(elapsed.components.seconds) * 1e6)
    }
    samples.sort()
    let median = samples[frames / 2]
    let p99 = samples[frames * 99 / 100]
    print("  \(label.padding(toLength: 46, withPad: " ", startingAt: 0)) median \(Int(median)) us   p99 \(Int(p99)) us")
}

for (columns, rows) in [(120, 40), (300, 80)] {
    print("\(columns)x\(rows)")
    var state = ScreenState(label: "claude-sonnet-5-5")
    for index in 0 ..< 200 {
        state.transcript.addNotice(String(repeating: "word ", count: columns / 6) + "\(index)", isError: false)
    }
    let pipeline = RenderPipeline(connection: MockTerminalConnection(), columns: columns, rows: rows)
    var composer = ScreenComposer()
    _ = composer.compose(state, into: &pipeline.buffer)
    try? pipeline.forceRedraw()
    measure("keystroke: layout + flush") { iteration in
        state.editor.paste(iteration % 2 == 0 ? "x" : "y")
        pipeline.beginFrame()
        _ = composer.compose(state, into: &pipeline.buffer)
        try? pipeline.flush()
    }
    measure("keystroke: layout only (compose, no flush)") { iteration in
        state.editor.paste(iteration % 2 == 0 ? "x" : "y")
        _ = composer.compose(state, into: &pipeline.buffer)
        pipeline.buffer.dirty.clear()
    }
    measure("keystroke: flush only (one cell written)") { iteration in
        pipeline.beginFrame()
        pipeline.buffer.write(iteration % 2 == 0 ? "x" : "y", row: rows - 1, col: 5, style: .default)
        try? pipeline.flush()
    }
    measure("streamed line: layout + flush") { iteration in
        state.transcript.addNotice("streamed line \(iteration) of ordinary length", isError: false)
        pipeline.beginFrame()
        _ = composer.compose(state, into: &pipeline.buffer)
        try? pipeline.flush()
    }
}
