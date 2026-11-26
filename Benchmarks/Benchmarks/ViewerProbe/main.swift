import AskTUI
import Darwin
import TerminalKitRender

// ADR-0170, t150: what one more viewer of a live session costs the node. Each viewer is a screen of its own (ScreenController fed
// the conversation's updates, composed at the viewer's size), so the cost of N viewers is N times one screen: the memory of its
// transcript, and per streamed update the frame (layout and diff) at its size. Run in release:
//   cd Benchmarks && swift run -c release ViewerProbe [turns]

func resident() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.resident_size) : 0
}

/// A session's history as the conversation sends it: each turn a prompt, a reply of Markdown, and a command with its output.
func history(turns: Int) -> [ConversationUpdate] {
    var updates: [ConversationUpdate] = []
    let reply = (0 ..< 12).map { "- point \($0): **bold** and `code` with some ordinary words in it" }
        .joined(separator: "\n")
    let output = (0 ..< 60).map { "line \($0) of a command's output, of an ordinary length" }.joined(separator: "\n")
    for turn in 0 ..< turns {
        updates.append(.userPrompt("Please look at item \(turn) and tell me what you find there."))
        updates.append(.assistantText("Looking at it.\n\n" + reply))
        updates.append(.toolStarted(name: "bash", summary: "swift test --filter Item\(turn)", id: "c\(turn)"))
        updates.append(.toolFinished(.succeeded, output: output, id: "c\(turn)"))
        updates.append(.assistantText("Done with \(turn)."))
    }
    return updates
}

struct Viewer {
    var controller: ScreenController
    var composer = ScreenComposer()
    var front: ScreenBuffer
    var back: ScreenBuffer

    init(columns: Int, rows: Int) {
        controller = ScreenController(label: "claude-sonnet-5-5")
        controller.setScreenRows(rows)
        front = ScreenBuffer(columns: columns, rows: rows)
        back = ScreenBuffer(columns: columns, rows: rows)
    }

    mutating func apply(_ update: ConversationUpdate) { _ = controller.handle(update) }

    /// One frame: layout and diff, the bytes a viewer's terminal would receive.
    mutating func frame() -> Int {
        _ = composer.compose(controller.state, into: &back)
        let bytes = DiffRenderer.render(front: front, back: back)
        front = back
        back.dirty.clear()
        return bytes.count
    }
}

func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

let turns = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 400
let past = history(turns: turns)
print("history: \(turns) turns, \(past.count) updates")

// Memory: viewers built one after another, each fed the whole history, as a viewer joining a live session is.
var viewers: [Viewer] = []
let sizes = [(120, 40), (80, 24), (200, 60), (100, 30)]
var last = resident()
for (index, size) in sizes.enumerated() {
    var viewer = Viewer(columns: size.0, rows: size.1)
    for update in past { viewer.apply(update) }
    _ = viewer.frame()
    viewers.append(viewer)
    let now = resident()
    print(
        String(
            format: "viewer %d (%dx%d): +%.1f MiB resident",
            index + 1,
            size.0,
            size.1,
            Double(now - last) / 1_048_576
        )
    )
    last = now
}

// Time: a streamed reply, one delta at a time, with a frame for each viewer after each delta; per viewer and frame.
let clock = ContinuousClock()
for count in [1, 2, 4] {
    var times: [Double] = []
    var bytes = 0
    for round in 0 ..< 300 {
        let delta = ConversationUpdate.assistantText(
            round % 20 == 0 ? "\n\nA new paragraph: " : "more words of the reply "
        )
        let start = clock.now
        for index in 0 ..< count {
            viewers[index].apply(delta)
            bytes += viewers[index].frame()
        }
        let elapsed = clock.now - start
        times.append(Double(elapsed.components.attoseconds) / 1e12 + Double(elapsed.components.seconds) * 1e6)
    }
    print(
        String(
            format:
                "%d viewer(s): median %.0f µs per streamed delta (all viewers), %.0f µs per viewer; %d B per viewer-frame",
            count,
            median(times),
            median(times) / Double(count),
            bytes / (300 * count)
        )
    )
}
