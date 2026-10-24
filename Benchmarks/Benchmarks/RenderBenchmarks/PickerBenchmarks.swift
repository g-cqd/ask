import AskTUI
import Benchmark
import TerminalKitCodecs
import TerminalKitInput
import TerminalKitRender

/// The cost the command picker adds to a keystroke (ADR-0067, roadmap 0048). The picker is looked for after every key, so the case
/// that matters is the ordinary one, a keystroke with no slash anywhere, where the answer must cost next to nothing, even in a long
/// draft. Public API only, so the identical code measures a tree that has no picker: there the slash cases are plain typing.
func registerPickerBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal], maxDuration: .seconds(1), maxIterations: 1_000)
    let commands = ["config", "compact", "reload", "new", "resume", "model", "models", "connections", "sessions"]
        .map { SlashCommand(name: $0, summary: "Does the thing the name says, for \($0).") }
    let pageRows = 37
    func key(_ code: UInt32) -> InputEvent { .key(KeyEvent(keyCode: code)) }
    let backspace = key(0x7F)

    func controller(_ draft: String) -> ScreenController {
        var controller = ScreenController(label: "model", commands: commands)
        _ = controller.handle(.paste(draft), pageRows: pageRows, columns: 120)
        return controller
    }

    let longDraft = (0 ..< 100).map { _ in String(repeating: "word ", count: 12) }.joined(separator: "\n")
    for (name, draft) in [
        ("an empty draft", ""), ("a 100-line draft (6 KB), cursor at the end", longDraft),
        ("a slash word that matches (/co)", "/co")
    ] {
        Benchmark("picker/keystroke and backspace in \(name)", configuration: configuration) { benchmark in
            var screen = controller(draft)
            let letter = key(UInt32(Character("m").asciiValue!))
            benchmark.startMeasurement()
            blackHole(screen.handle(letter, pageRows: pageRows, columns: 120))
            blackHole(screen.handle(backspace, pageRows: pageRows, columns: 120))
            benchmark.stopMeasurement()
        }
    }

    Benchmark("picker/Down in an open list (or a plain Down where there is none)", configuration: configuration) {
        benchmark in
        var screen = controller("/co")
        let down = key(Key.down.rawValue)
        benchmark.startMeasurement()
        blackHole(screen.handle(down, pageRows: pageRows, columns: 120))
        benchmark.stopMeasurement()
    }

    Benchmark("picker/frame with /co typed, 120x40", configuration: configuration) { benchmark in
        let screen = controller("/co")
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
