internal import Darwin
internal import Foundation
internal import Synchronization

/// An exclusive advisory lock beside the credential file, shared by every ask process on this machine.
///
/// There are two, because they guard different things for different lengths of time. The refresh lock (no name) is held
/// across a network call, so that a rotating refresh token is spent once. The save lock (`"write"`) is held for the few
/// milliseconds of a read, a change and a rename, so that two saves cannot read the same file and each erase the
/// other's change. The order is always refresh then save, and nothing takes them the other way round: flock is per open
/// file description, so a second descriptor in the same process blocks exactly as another process does.
///
/// A lock is let go when it is told to, when the object is dropped, and by the system when the process ends, so a
/// crash or a forgotten release cannot leave it held.
final class CredentialLock: Sendable {
    /// Why a lock could not be taken.
    enum Failure: Error, Equatable, Sendable {
        /// Another process held it for the whole wait.
        case timedOut
        /// The task was cancelled while waiting.
        case cancelled
        /// The lock file could not be opened or locked.
        case io(CredentialFileError)
    }

    private enum Step {
        case held
        case retry
        case timedOut
        case failed(Int32)
    }

    private let descriptor: Mutex<Int32?>

    private init(descriptor: Int32) { self.descriptor = Mutex(descriptor) }

    deinit { release() }

    /// Where the lock named `name` for the credentials at `url` lives; no name is the refresh lock.
    static func path(beside url: URL, name: String) -> String {
        url.path + (name.isEmpty ? "" : "." + name) + ".lock"
    }

    /// Takes the lock beside `url`, waiting up to `wait` for whoever holds it, without blocking a thread.
    /// - Parameters:
    ///   - url: the credential file the lock guards.
    ///   - wait: the longest to wait.
    ///   - name: which lock; none is the refresh lock.
    /// - Returns: the held lock; call ``release()`` when done.
    /// - Throws: a ``Failure``.
    // @dl:accept -- the async and blocking waits differ only in how they pause, and one must be async while the other must not be
    static func acquire(beside url: URL, wait: Duration, name: String = "") async throws(Failure) -> CredentialLock {
        let (descriptor, deadline) = try open(beside: url, name: name, wait: wait)
        while true {
            if let lock = try settle(step(descriptor, deadline: deadline), descriptor, url, name) { return lock }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { throw give(up: descriptor, .cancelled) }
        }
    }

    /// Takes the lock, waiting on this thread. For a lock held only for a read, a change and a rename, where the wait is
    /// milliseconds and a caller that is not `async` has nowhere else to wait.
    /// - Throws: a ``Failure``; never `cancelled`.
    static func acquireBlocking(beside url: URL, wait: Duration, name: String) throws(Failure) -> CredentialLock {
        let (descriptor, deadline) = try open(beside: url, name: name, wait: wait)
        while true {
            if let lock = try settle(step(descriptor, deadline: deadline), descriptor, url, name) { return lock }
            usleep(2_000)
        }
    }

    /// Lets go of the lock. Letting go twice is harmless.
    func release() {
        guard
            let held = descriptor.withLock({ (value: inout Int32?) -> Int32? in
                defer { value = nil }
                return value
            })
        else { return }
        flock(held, LOCK_UN)
        close(held)
    }

    private static func open(beside url: URL, name: String, wait: Duration) throws(Failure) -> (
        Int32, ContinuousClock.Instant
    ) {
        let path = path(beside: url, name: name)
        let descriptor = Darwin.open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .io(.io(path: path, errno: errno)) }
        return (descriptor, ContinuousClock().now.advanced(by: wait))
    }

    private static func step(_ descriptor: Int32, deadline: ContinuousClock.Instant) -> Step {
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return .held }
        let failure = errno
        guard failure == EWOULDBLOCK else { return .failed(failure) }
        return ContinuousClock().now < deadline ? .retry : .timedOut
    }

    /// The lock when `step` took it, nil when the caller should wait and try again, and a failure otherwise.
    private static func settle(_ step: Step, _ descriptor: Int32, _ url: URL, _ name: String) throws(Failure)
        -> CredentialLock?
    {
        switch step {
            case .held: return CredentialLock(descriptor: descriptor)
            case .retry: return nil
            case .timedOut: throw give(up: descriptor, .timedOut)
            case .failed(let code):
                throw give(up: descriptor, .io(.io(path: path(beside: url, name: name), errno: code)))
        }
    }

    private static func give(up descriptor: Int32, _ failure: Failure) -> Failure {
        close(descriptor)
        return failure
    }
}
