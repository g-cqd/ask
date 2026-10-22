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

    /// The measured bypass key for this terminal, or the configuration switch when the terminal is unknown.
    var nativeSelectionHint: String {
        writer.identity.nativeSelectionKey.map { "\($0): native selection" } ?? "native selection: ui.mouse false"
    }

    /// Reports what was requested, not an acknowledgement from the terminal or completion of the host's pasteboard command.
    @discardableResult
    mutating func copy(_ text: String) -> String {
        let plan = writer.plan(copying: text)
        var failure: String?
        if let bytes = plan.terminal {
            do { try connection.write(bytes) } catch { failure = String(describing: error) }
        }
        if plan.usePasteboard {
            pasteboard(text)
            if let failure { return "Terminal copy failed: \(failure); host copy queued" }
            return plan.terminal == nil ? "Host copy queued" : "Copy sent to terminal; host copy queued"
        }
        if let failure { return "Copy failed: \(failure)" }
        switch plan.outcome {
            case .terminal: return "Copy sent to terminal"
            case .tooLarge: return "Copy too large for this terminal"
            case .nothing: return "Nothing selected"
            default: return "Copy unavailable on this connection"
        }
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
