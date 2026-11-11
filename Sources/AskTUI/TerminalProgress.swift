/// Progress for the terminal (notes n59 and n61; the owner's answers of 2026-11-11): once a turn, a compaction or a command in the
/// foreground has gone on ``LongAction/after``, the tab shows it. OSC 9;4 asks the terminal for its own busy mark, sent only where it
/// is known to be read so: OSC 9 is also a notification, and a terminal older than its progress form shows "4;3" as one. Everywhere
/// a spinner leads the tab's title (``TabTitle``).
enum TerminalProgress {
    /// Busy, for as long as it takes: OSC 9;4 state 3.
    static let working = Array("\u{1B}]9;4;3\u{1B}\\".utf8)
    /// Done: OSC 9;4 state 0 takes the mark away.
    static let done = Array("\u{1B}]9;4;0\u{1B}\\".utf8)

    /// The first versions that read OSC 9;4 as progress: iTerm2 3.6 and Ghostty 1.2. Others are not sent it, nor anything behind tmux,
    /// which hides the terminal.
    private static let firstReading: [String: [Int]] = ["iTerm.app": [3, 6], "ghostty": [1, 2]]

    /// Whether the terminal `environment` describes reads OSC 9;4 as progress.
    static func isRead(environment: [String: String]) -> Bool {
        guard environment["TMUX"] == nil, let program = environment["TERM_PROGRAM"], let first = firstReading[program],
            let version = environment["TERM_PROGRAM_VERSION"]
        else { return false }
        let parts = version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        return parts.lexicographicallyPrecedes(first) == false
    }

    /// How long each of the tab's spinner frames shows: a title is redrawn by the terminal, so four a second, not the status line's rate.
    static let frameLength = Duration.milliseconds(250)

    /// The spinner's frame `elapsed` into the work, its first as the work becomes long; nil without frames.
    static func frame(after elapsed: Duration, of frames: [String]) -> String? {
        guard !frames.isEmpty else { return nil }
        let step = Swift.max(0, Int((elapsed - LongAction.after) / frameLength))
        return frames[step % frames.count]
    }
}
