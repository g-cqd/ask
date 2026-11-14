internal import Synchronization

/// The commands the check before a run had nothing to say about (they parse, and shellcheck found nothing), which are not checked again
/// (the owner's choice, 2026-11-14). The check costs up to 30 ms on every command (shellcheck's start alone is 21), and an agent sends
/// the same build and test commands over and over. What the check says depends on the command's text, the shell that parses it and
/// the PATH shellcheck is found on, and on nothing else, so a command is remembered for those three.
///
/// Bounded: a command longer than ``maximumBytes`` is checked every time, a changed PATH forgets everything, and so does the
/// ``kept``-th command.
final class CleanCommands: Sendable {
    static let kept = 256
    static let maximumBytes = 4096
    private let state = Mutex<(path: String?, keys: Set<String>)>((nil, []))

    /// Whether `command` was found clean for `shell` under `path`.
    func contains(_ command: String, shell: String, path: String?) -> Bool {
        state.withLock { $0.path == path && $0.keys.contains(Self.key(command, shell)) }
    }

    /// Remembers that `command` was found clean for `shell` under `path`.
    func remember(_ command: String, shell: String, path: String?) {
        guard command.utf8.count <= Self.maximumBytes else { return }
        state.withLock { state in
            if state.path != path || state.keys.count >= Self.kept { state = (path, []) }
            state.keys.insert(Self.key(command, shell))
        }
    }

    private static func key(_ command: String, _ shell: String) -> String { shell + "\u{0}" + command }
}
