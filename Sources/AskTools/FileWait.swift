internal import AemiIO
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
        guard let watch = DirectoryWatch(directory: directory) else { return false }
        // A change between choosing the directory and watching it raised no event: look again now that the
        // watch is set, or that change is missed and the wait never ends.
        if FileManager.default.fileExists(atPath: path) || deepestExisting(path) != directory {
            watch.close()
            return true
        }
        let changed = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                Thread { continuation.resume(returning: watch.next()) }.start()
            }
        } onCancel: {
            watch.wake()
        }
        watch.close()
        return changed && !Task.isCancelled
    }
}
