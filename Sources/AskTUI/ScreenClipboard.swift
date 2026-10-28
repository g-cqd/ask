internal import TerminalKitIO
internal import TerminalKitInput

/// Carries out TerminalKit's clipboard plan (ADR-0028): the escape sequence to the terminal, and the host's pasteboard where the
/// terminal cannot be trusted to take it. The kit decides; this performs, so a test supplies its own pasteboard and never touches the
/// real one.
struct ScreenClipboard {
    private var writer: ClipboardWriter
    private let connection: any TerminalConnection
    private let pasteboard: @Sendable (String) async -> PasteboardResult
    /// Reads the host's pasteboard for a Command+V or Ctrl+V the terminal passed on instead of pasting (roadmap 0082).
    let read: @Sendable () async -> HostPasteboard.Reading

    init(
        connection: any TerminalConnection, environment: [String: String],
        pasteboard: @escaping @Sendable (String) async -> PasteboardResult,
        read: @escaping @Sendable () async -> HostPasteboard.Reading = { .empty }
    ) {
        writer = ClipboardWriter(environment: environment)
        self.connection = connection
        self.pasteboard = pasteboard
        self.read = read
    }

    /// Reads the pasteboard and hands its text to the screen as a bracketed paste, or why it could not (roadmap 0082).
    func paste(into sink: AsyncStream<ScreenEvent>.Continuation) {
        let read = read
        Task {
            switch await read() {
                case .text(let text): sink.yield(.input(.paste(text)))
                case .denied(let reason): sink.yield(.pasteRefused(reason))
                case .empty: break
            }
        }
    }

    /// The measured bypass key for this terminal, or the configuration switch when the terminal is unknown.
    var nativeSelectionHint: String {
        writer.identity.nativeSelectionKey.map { "\($0): native selection" } ?? "native selection: ui.mouse false"
    }

    /// Performs the copy and says what is known now. A terminal write that did not fail is reported as *sent*, never acknowledged: OSC 52
    /// has no reply. The host pasteboard command is observed: `finished` is called once, later, with what happened to it.
    /// - Parameters:
    ///   - text: What to copy.
    ///   - finished: The final notice and whether it is a failure, for a copy that went to the host pasteboard.
    /// - Returns: the notice to show at once.
    mutating func copy(_ text: String, finished: @escaping @Sendable (_ notice: String, _ failed: Bool) -> Void)
        -> String
    {
        let plan = writer.plan(copying: text)
        var failure: String?
        if let bytes = plan.terminal {
            do { try connection.write(bytes) } catch { failure = String(describing: error) }
        }
        let terminal =
            plan.terminal == nil ? nil : (failure.map { "Terminal copy failed: \($0)" } ?? "Copy sent to terminal")
        if plan.usePasteboard {
            let pasteboard = pasteboard
            Task {
                let result = await pasteboard(text)
                switch result {
                    case .copied: finished(Self.say(terminal, "copied to host clipboard"), false)
                    case .failed(let reason): finished(Self.say(terminal, "host copy failed: \(reason)"), true)
                }
            }
            return Self.say(terminal, "host copy pending")
        }
        if let failure { return "Copy failed: \(failure)" }
        switch plan.outcome {
            case .terminal: return "Copy sent to terminal"
            case .tooLarge: return "Copy too large for this terminal"
            case .nothing: return "Nothing selected"
            default: return "Copy unavailable on this connection"
        }
    }

    /// `terminal; host`, or the host part alone with its first letter capitalised.
    private static func say(_ terminal: String?, _ host: String) -> String {
        terminal.map { "\($0); \(host)" } ?? host.prefix(1).uppercased() + host.dropFirst()
    }
}
