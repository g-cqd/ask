internal import Darwin
internal import Foundation
internal import Synchronization

/// Reports each new build of ask that appears while it runs (ADR-0033).
///
/// kqueue watches the executable's *directory*: a linker writes a new file and swaps it in, so the old file's own
/// descriptor sees only a deletion, while the directory sees the change (probed). Each event is a reason to
/// look again, and a new identity is reported only when the file at the path differs from the last one reported.
/// A link raises several events as it writes, so a consumer should treat the first as "a build appeared" and not
/// as "the build is finished": the self-check at reload time is what decides that.
///
/// The wait blocks in `kevent` on a thread of its own, never on the cooperative pool, and a user event wakes it
/// when the stream ends. A file rewritten in place, with no change to the directory, is not seen; the linker
/// does not do that.
public enum BinaryWatcher {
    /// New identities of the file `identity` names, until the stream is cancelled.
    /// - Parameters:
    ///   - identity: the build that is running.
    ///   - stopped: called once, on the watcher's thread, after it closed its two descriptors, saying whether each
    ///     `close` succeeded. For tests.
    /// - Returns: the new identities, each reported once, ending when the stream's consumer is cancelled.
    public static func changes(
        since identity: BinaryIdentity,
        stopped: (@Sendable (_ queueClosed: Bool, _ directoryClosed: Bool) -> Void)? = nil
    ) -> AsyncStream<BinaryIdentity> {
        AsyncStream { continuation in
            guard let watch = DirectoryWatch(directory: (identity.path as NSString).deletingLastPathComponent) else {
                continuation.finish()
                stopped?(true, true)
                return
            }
            // After the descriptors are closed no one may signal the queue: its number could be reused.
            let live = Mutex(true)
            continuation.onTermination = { _ in
                live.withLock { live in
                    if live { watch.wake() }
                }
            }
            Thread {
                var last = identity
                func report() {
                    if let now = BinaryIdentity(path: identity.path), now != last {
                        last = now
                        continuation.yield(now)
                    }
                }
                // A build that landed between the caller's look and this watch raised no event.
                report()
                while watch.next() { report() }
                let closed: (queue: Bool, directory: Bool) = live.withLock { live in
                    live = false
                    return watch.close()
                }
                continuation.finish()
                stopped?(closed.queue, closed.directory)
            }
            .start()
        }
    }
}
