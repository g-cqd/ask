internal import Darwin
internal import Foundation
internal import Synchronization

/// An exclusive advisory lock beside the credential file, shared by every ask process on this machine.
///
/// A rotating refresh token is spent by the refresh that uses it, so "read the credentials, refresh, save the
/// replacement" must be one step no other process interleaves with. The lock is released when this object is told to,
/// and by the system when the process ends, so a crash cannot leave it held.
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

    private let descriptor: Mutex<Int32?>

    private init(descriptor: Int32) { self.descriptor = Mutex(descriptor) }

    /// Takes the lock beside `url`, waiting up to `wait` for whoever holds it.
    /// - Parameters:
    ///   - url: the credential file the lock guards.
    ///   - wait: the longest to wait.
    /// - Returns: the held lock; call ``release()`` when done.
    /// - Throws: a ``Failure``.
    static func acquire(beside url: URL, wait: Duration) async throws(Failure) -> CredentialLock {
        let path = url.path + ".lock"
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .io(.io(path: path, errno: errno)) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: wait)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let failure = errno
            guard failure == EWOULDBLOCK else {
                close(descriptor)
                throw .io(.io(path: path, errno: failure))
            }
            guard clock.now < deadline else {
                close(descriptor)
                throw .timedOut
            }
            do { try await Task.sleep(for: .milliseconds(25)) } catch {
                close(descriptor)
                throw .cancelled
            }
        }
        return CredentialLock(descriptor: descriptor)
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
}
