internal import AskTools
internal import Darwin
internal import Synchronization

/// A conversation's skills while it runs: the shelf its loops' `skill` tool serves, and the trust store as last seen, so a skill
/// the person trusts in another terminal (`ask trust --skills`) reaches the model at their next message without a restart.
final class SessionSkills: Sendable {
    let shelf = SkillShelf()
    /// The trust store's modification time and size when last looked at; nil before the first look.
    private let seen = Mutex<[Int]?>(nil)

    /// Whether the trust store at `path` changed since the last look, which this one becomes. The first look only remembers it:
    /// the loop reads the skills when it is made. A `stat`, not a read: re-reading the skills took 7.3 ms (53 skills).
    func trustChanged(at path: String) -> Bool {
        var info = stat()
        let now =
            stat(path, &info) == 0
            ? [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, Int(info.st_size)] : [0, 0, -1]
        return seen.withLock { seen in
            defer { seen = now }
            return seen.map { $0 != now } ?? false
        }
    }
}
