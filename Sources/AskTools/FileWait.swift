internal import Darwin
internal import Foundation
internal import Synchronization

/// Waits for a path to exist, on kernel events (ADR-0027): kqueue watches the deepest directory of the path
/// that exists, and every change there is a reason to look again. The wait blocks in `kevent` on a thread of
/// its own, never on a cooperative thread, and a user event wakes it when the task is cancelled.
enum FileWait {
    /// Waits until `path` exists.
    /// - Returns: true once it exists; false when the task was cancelled first or the directory cannot be
    ///   watched.
    static func until(exists path: String) async -> Bool {
        while !Task.isCancelled {
            if FileManager.default.fileExists(atPath: path) { return true }
            guard await directoryChanged(deepestExisting(path), awaiting: path) else { return false }
        }
        return false
    }

    /// The nearest ancestor of `path` that exists, which is where its next component will appear.
    static func deepestExisting(_ path: String) -> String {
        var candidate = (path as NSString).deletingLastPathComponent
        while !candidate.isEmpty, candidate != "/", !FileManager.default.fileExists(atPath: candidate) {
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return candidate.isEmpty ? "." : candidate
    }

    /// Waits for one change to `directory`, or returns at once if `path` moved on while the watch was set up.
    /// - Returns: false when cancelled or when the directory cannot be watched.
    private static func directoryChanged(_ directory: String, awaiting path: String) async -> Bool {
        let queue = kqueue()
        let watched = open(directory, O_EVTONLY)
        guard queue >= 0, watched >= 0 else {
            if queue >= 0 { close(queue) }
            if watched >= 0 { close(watched) }
            return false
        }
        var changes = [
            kevent(
                ident: UInt(watched), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_CLEAR),
                fflags: UInt32(NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_LINK), data: 0, udata: nil),
            kevent(
                ident: 1, filter: Int16(EVFILT_USER), flags: UInt16(EV_ADD | EV_CLEAR), fflags: 0, data: 0,
                udata: nil)
        ]
        guard unsafe kevent(queue, &changes, 2, nil, 0, nil) == 0 else {
            close(queue)
            close(watched)
            return false
        }
        // A change between choosing the directory and watching it raised no event: look again now that the
        // watch is set, or that change is missed and the wait never ends.
        if FileManager.default.fileExists(atPath: path) || deepestExisting(path) != directory {
            close(queue)
            close(watched)
            return true
        }
        let changed = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let thread = Thread {
                    var event = kevent()
                    let count = unsafe kevent(queue, nil, 0, &event, 1, nil)
                    continuation.resume(returning: count == 1 && event.filter == Int16(EVFILT_VNODE))
                }
                thread.start()
            }
        } onCancel: {
            var wake = kevent(
                ident: 1, filter: Int16(EVFILT_USER), flags: 0, fflags: UInt32(NOTE_TRIGGER), data: 0, udata: nil)
            _ = unsafe kevent(queue, &wake, 1, nil, 0, nil)
        }
        close(queue)
        close(watched)
        return changed && !Task.isCancelled
    }
}
