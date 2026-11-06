internal import Testing

@testable import AskTUI

/// What `read`, `write` and `edit` blocks draw as with highlighting off: written before files were highlighted (roadmap 0152, phase 3),
/// so that `ui.highlight` off is ask as it was, row for row. A change to the digest is a change to the off path, and must be deliberate.
@Suite("With highlighting off, file tool blocks draw as they did before highlighting")
struct FileToolCharacterisationTests {
    /// A tool, the path it names, its input, its output, and whether it failed.
    struct Call {
        var name: String
        var path: String
        var input: String
        var output: String
        var failed = false
    }

    static let swift =
        "/* a\n\tstill */ @MainActor func f() -> Int {\n\treturn 0x1F // done, é and 漢字\n}\nlet s = \"text\""
    static let calls = [
        Call(name: "read", path: "Sources/a.swift", input: "{\n  \"path\": \"Sources/a.swift\"\n}", output: swift),
        Call(
            name: "read",
            path: "tool.py",
            input: "{\n  \"path\": \"tool.py\",\n  \"offset\": 2\n}",
            output: "def f(a=1.5e-3): '''doc\nmore'''\n[lines 2–3 of 3]"
        ),
        Call(name: "read", path: "run", input: "{\n  \"path\": \"run\"\n}", output: "#!/bin/sh\necho \"$HOME\" # c"),
        Call(
            name: "read",
            path: "gone.swift",
            input: "{\n  \"path\": \"gone.swift\"\n}",
            output: "no such file",
            failed: true
        ),
        Call(
            name: "read",
            path: "long.rs",
            input: "{\n  \"path\": \"long.rs\"\n}",
            output: (1 ... 30).map { "let v\($0) = r#\"x\"#; // \($0)" }.joined(separator: "\n")
        ),
        Call(
            name: "write",
            path: "b.json",
            input: "{\"key\": [1, true, null, \"s\"]}",
            output: "Wrote 30 bytes to b.json."
        ),
        Call(
            name: "edit",
            path: "c.lua",
            input: "old_text:\nlocal s = 1\nnew_text:\nlocal s = [[long\nstring]] -- c",
            output: "Replaced 1 occurrence in c.lua."
        )
    ]

    static func transcript(_ call: Call) -> Transcript {
        var transcript = Transcript()
        transcript.setOutputFoldLimits(lines: 10, bytes: 1 << 20)
        transcript.startTool(name: call.name, summary: call.path, id: "call", fullInput: call.input)
        transcript.finishTool(call.failed ? .failed(call.output) : .succeeded, output: call.output, id: "call")
        transcript.setToolsFoldedByDefault(false)
        return transcript
    }

    static func digest() -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for call in calls {
            let transcript = transcript(call)
            for columns in 1 ... 80 {
                for style in [BlockStyle.plain, BlockStyle()] {
                    let rendering = ScreenComposer.lines(in: transcript, at: 0, columns: columns, style: style)
                        .map { "\($0.text)|\($0.style)|\($0.accents)|\($0.links)|\(String(describing: $0.source))" }
                        .joined(separator: "\n")
                    for byte in rendering.utf8 {
                        hash ^= UInt64(byte)
                        hash &*= 0x100_0000_01B3
                    }
                }
            }
        }
        return hash
    }

    // Moved on purpose (note n11): a single `/word` outside the root's folders is no longer linked as a path.
    @Test func `the rows of file tool blocks with highlighting off keep their digest`() {
        #expect(Self.digest() == 4_547_764_615_977_946_759)
    }
}
