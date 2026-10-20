internal import Foundation
internal import TerminalKitIO
internal import TerminalKitInput

/// Carries out TerminalKit's clipboard plan (ADR-0028): the escape sequence to the terminal, and the host's pasteboard where the
/// terminal cannot be trusted to take it. The kit decides; this performs, so a test supplies its own pasteboard and never touches the
/// real one.
struct ScreenClipboard {
    private var writer: ClipboardWriter
    private let connection: any TerminalConnection
    private let pasteboard: @Sendable (String) -> Void

    init(
        connection: any TerminalConnection, environment: [String: String],
        pasteboard: @escaping @Sendable (String) -> Void
    ) {
        writer = ClipboardWriter(environment: environment)
        self.connection = connection
        self.pasteboard = pasteboard
    }

    mutating func copy(_ text: String) {
        let plan = writer.plan(copying: text)
        if let bytes = plan.terminal { try? connection.write(bytes) }
        if plan.usePasteboard { pasteboard(text) }
    }

    /// macOS's pasteboard, through `pbcopy`, off the caller's thread: a copy never waits for it.
    static let pbcopy: @Sendable (String) -> Void = { text in
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
            let pipe = Pipe()
            process.standardInput = pipe
            guard (try? process.run()) != nil else { return }
            try? pipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try? pipe.fileHandleForWriting.close()
        }
    }
}
