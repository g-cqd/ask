import AskTUI
import Benchmark
import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender

/// The cost the `@` file picker adds to a keystroke (ADR-0069, roadmap 0048): ranking a project's files against what is typed, after
/// every key, on the input thread. The listing is 20,000 paths (the lister's limit) of the usual shape, so this is the worst case the
/// picker allows. Needs the picker's types, so it does not build on a tree without them; the keystroke cost of a draft that has no
/// at sign is in `PickerBenchmarks`, which builds on both.
func registerFilePickerBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal], maxDuration: .seconds(1), maxIterations: 1_000)
    let pageRows = 37
    func key(_ character: Character) -> InputEvent {
        .key(KeyEvent(keyCode: UInt32(character.asciiValue!)))
    }
    let backspace = InputEvent.key(KeyEvent(keyCode: 0x7F))
    let paths = (0 ..< 20_000)
        .map { index in
            "Sources/Module\(index % 40)/Group\(index % 97)/File\(index)Handler.swift"
        }
    let listing = ProjectFiles(paths: paths)

    func controller(_ draft: String) -> ScreenController {
        var controller = ScreenController(label: "model", commands: [])
        _ = controller.handle(.files(listing))
        _ = controller.handle(.paste(draft), pageRows: pageRows, columns: 120)
        return controller
    }

    for (name, draft) in [
        ("one letter, every file matches a name", "@h"), ("a name most files contain", "@hand"),
        ("a name no file contains", "@zzzz"), ("a path prefix", "@Sources/Module3/")
    ] {
        Benchmark("files/keystroke and backspace after \(name) (20,000 files)", configuration: configuration) {
            benchmark in
            var screen = controller(draft)
            benchmark.startMeasurement()
            blackHole(screen.handle(key("a"), pageRows: pageRows, columns: 120))
            blackHole(screen.handle(backspace, pageRows: pageRows, columns: 120))
            benchmark.stopMeasurement()
        }
    }

    Benchmark("files/frame with @hand typed, 120x40", configuration: configuration) { benchmark in
        let screen = controller("@hand")
        var buffer = ScreenBuffer(columns: 120, rows: 40)
        var composer = ScreenComposer()
        _ = composer.compose(screen.state, into: &buffer)
        var state = screen.state
        state.transcript.addNotice("tick", isError: false)
        benchmark.startMeasurement()
        blackHole(composer.compose(state, into: &buffer))
        benchmark.stopMeasurement()
    }
}
