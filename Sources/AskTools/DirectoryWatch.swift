internal import Darwin
internal import Foundation

/// A kqueue watching one directory for entries being added, removed or renamed, and a user event that wakes
/// whoever is waiting on it (ADR-0029, ADR-0034).
///
/// A file saved by writing a new one and renaming it over the old shows up as a change to the *directory*;
/// the old file's own descriptor only sees a deletion. So both the wait for a file to appear and the watch
/// for a rebuilt executable watch the directory and look again at each change.
///
/// ``next()`` blocks, so it belongs on a thread of its own, never on the cooperative pool.
struct DirectoryWatch: Sendable {
    private let queue: Int32
    private let directory: Int32

    /// Opens `path`, a directory, and registers for its changes; nil if either step fails.
    init?(directory path: String) {
        let queue = kqueue()
        let directory = open(path, O_EVTONLY)
        var changes = [
            kevent(
                ident: UInt(directory), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_CLEAR),
                fflags: UInt32(NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_LINK | NOTE_ATTRIB), data: 0,
                udata: nil),
            kevent(
                ident: 1, filter: Int16(EVFILT_USER), flags: UInt16(EV_ADD | EV_CLEAR), fflags: 0, data: 0,
                udata: nil)
        ]
        guard queue >= 0, directory >= 0, unsafe kevent(queue, &changes, 2, nil, 0, nil) == 0 else {
            if queue >= 0 { Darwin.close(queue) }
            if directory >= 0 { Darwin.close(directory) }
            return nil
        }
        self.queue = queue
        self.directory = directory
    }

    /// Blocks until the directory changes.
    /// - Returns: true for a change; false when ``wake()`` ended the wait, or the queue failed.
    func next() -> Bool {
        var event = kevent()
        let count = unsafe kevent(queue, nil, 0, &event, 1, nil)
        return count == 1 && event.filter == Int16(EVFILT_VNODE)
    }

    /// Ends a blocked ``next()``, which then returns false. Do not call after ``close()``: the descriptor's number
    /// could belong to something else by then.
    func wake() {
        var wake = kevent(
            ident: 1, filter: Int16(EVFILT_USER), flags: 0, fflags: UInt32(NOTE_TRIGGER), data: 0, udata: nil)
        _ = unsafe kevent(queue, &wake, 1, nil, 0, nil)
    }

    /// Closes both descriptors.
    /// - Returns: whether each `close` succeeded, which means it was open and is closed exactly once. For tests: a
    ///   descriptor's number may be reused by another thread at once, so asking whether it is invalid would race.
    @discardableResult
    func close() -> (queue: Bool, directory: Bool) {
        (Darwin.close(queue) == 0, Darwin.close(directory) == 0)
    }
}
