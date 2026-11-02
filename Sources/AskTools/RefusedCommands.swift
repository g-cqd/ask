internal import Synchronization

/// The commands refused once for shellcheck's findings (the owner's choice, 2026-11-02): sending the same command again runs it as written,
/// and uses that up. A few are kept, the oldest forgotten first.
final class RefusedCommands: Sendable {
    private let keys = Mutex<[String]>([])
    static let kept = 16

    /// Whether `command`, for `shell`, is refused now: true the first time, false when it was refused before (and then forgotten).
    func refuses(_ command: String, shell: String) -> Bool {
        let key = shell + "\u{0}" + command
        return keys.withLock { keys in
            if let index = keys.firstIndex(of: key) {
                keys.remove(at: index)
                return false
            }
            keys.append(key)
            if keys.count > Self.kept { keys.removeFirst() }
            return true
        }
    }
}
