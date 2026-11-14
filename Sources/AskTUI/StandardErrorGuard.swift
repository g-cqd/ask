internal import Darwin
internal import Synchronization

/// Keeps the process's standard error off the terminal while the screen is drawn on it (the owner, 2026-11-14).
///
/// The screen is drawn on standard output, and standard error is the same terminal. Anything the process writes there lands on top
/// of the screen wherever the cursor is: ask writes none while the screen is open, but the libraries it links do (a system library
/// printed its database errors over the conversation). So for the screen's life standard error is a file, `stderr.log` in ask's
/// state folder; ``end()`` gives the terminal back and says how much was written, for ask to tell the person once the screen is
/// closed. A command ask starts has its own standard error (a pipe, or none); one that inherited this one would write to the file.
public final class StandardErrorGuard: Sendable {
    /// A log larger than this starts again when a guard begins.
    public static let maximumLogBytes = 1 << 20

    private struct State {
        var saved: Int32?
        var start: Int
    }

    private let descriptor: Int32
    private let logPath: String
    private let state: Mutex<State>

    /// Sends `descriptor` (standard error) to the file at `logPath`, made with its folder when missing, the person's alone.
    /// Nil, with nothing changed, when the file cannot be opened or the descriptor cannot be kept.
    /// - Parameters:
    ///   - logPath: the file standard error is sent to.
    ///   - descriptor: standard error, 2; a test gives another.
    public init?(logPath: String, descriptor: Int32 = 2) {
        let folder = String(logPath[..<(logPath.lastIndex(of: "/") ?? logPath.startIndex)])
        if !folder.isEmpty { _ = mkdir(folder, 0o700) }
        var status = stat()
        let large = stat(logPath, &status) == 0 && Int(status.st_size) > Self.maximumLogBytes
        let log = open(logPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | (large ? O_TRUNC : 0), 0o600)
        guard log >= 0 else { return nil }
        defer { close(log) }
        _ = fchmod(log, 0o600)
        let header = "--- ask \(getpid()) ---\n"
        _ = header.withCString { write(log, $0, strlen($0)) }
        let saved = fcntl(descriptor, F_DUPFD_CLOEXEC, 10)
        guard saved >= 0 else { return nil }
        guard dup2(log, descriptor) >= 0 else {
            close(saved)
            return nil
        }
        self.descriptor = descriptor
        self.logPath = logPath
        state = Mutex(State(saved: saved, start: Self.size(of: logPath)))
    }

    /// Gives the descriptor back what it was. Returns the bytes written to the log since the guard began; 0 when already ended.
    @discardableResult
    public func end() -> Int {
        let ended = state.withLock { state -> State? in
            guard state.saved != nil else { return nil }
            defer { state.saved = nil }
            return state
        }
        guard let ended, let saved = ended.saved else { return 0 }
        _ = dup2(saved, descriptor)
        close(saved)
        return max(0, Self.size(of: logPath) - ended.start)
    }

    private static func size(of path: String) -> Int {
        var status = stat()
        return stat(path, &status) == 0 ? Int(status.st_size) : 0
    }
}
