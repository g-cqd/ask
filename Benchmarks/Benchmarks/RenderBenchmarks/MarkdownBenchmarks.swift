import AskTUI
import Benchmark
import TerminalKitRender

/// Assistant replies drawn as Markdown (roadmap 0065, phase 4): what a streamed delta costs when the reply is parsed and drawn again whole, against
/// the same reply drawn as text.
func registerMarkdownBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.wallClock, .mallocCountTotal], maxDuration: .seconds(1), maxIterations: 1_000)
    /// A reply of `sections` sections, about 1.2 KB each, in the mix a model writes: a heading, prose with marks, a list, a table, a short fence.
    func reply(sections: Int) -> String {
        (0 ..< sections)
            .map { section in
                """
                ## Section \(section)

                Some **bold** prose with `code`, a [link](https://example.com/\(section)) and *emphasis*, long enough \
                to wrap at eighty columns more than once, as a model's paragraph does when it explains a change.

                - first item with `Sources/AskTUI/File\(section).swift:12`
                - second item, **done**
                  - nested item

                | Metric | Before | After |
                |---|---:|---:|
                | open | 227 ms | 41 ms |
                | RSS | 52.5 MiB | 20.1 MiB |

                ```swift
                let value = compute(\(section))
                print(value)
                ```
                """
            }
            .joined(separator: "\n\n")
    }
    for (name, sections) in [("9 KB", 8), ("58 KB", 48)] {
        for markdown in [true, false] {
            var state = ScreenState(label: "model")
            state.transcript.setMarkdown(markdown)
            for index in 0 ..< 50 { state.transcript.addNotice("earlier item \(index)", isError: false) }
            state.transcript.addAssistantText(reply(sections: sections))
            Benchmark(
                "markdown/stream delta, \(name) reply, \(markdown ? "markdown" : "text")", configuration: configuration
            ) { benchmark in
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
    }
}
