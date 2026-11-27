internal import Darwin
internal import Foundation
internal import Synchronization

/// Accepts connections on a listening socket, on one thread, as ``ProviderProxy`` does: the gateway's TCP doors and each ask process's
/// viewer socket. It owns the listener, and closes it once ``stop()`` wakes it.
package final class SocketAcceptor: Sendable {
    private let wake: Int32
    private let stopped = Atomic<Bool>(false)

    /// Starts accepting on `listener`, a bound, listening socket it now owns.
    /// - Parameters:
    ///   - listener: the listening socket.
    ///   - accept: receives each connected socket, blocking, on the accepting thread: it must hand it over, not serve it there.
    /// - Throws: ``TCPStream/Failure`` when the wake-up pipe cannot be made; the listener is closed then.
    package init(listener: Int32, accept: @escaping @Sendable (Int32) -> Void) throws(TCPStream.Failure) {
        var pipe: [Int32] = [-1, -1]
        guard Darwin.pipe(&pipe) == 0 else {
            let code = errno
            Darwin.close(listener)
            throw TCPStream.Failure(call: "pipe", code: code)
        }
        for descriptor in [listener] + pipe { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        // A connection gone between poll and accept must not block the thread, which then could not be woken.
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)
        wake = pipe[1]
        let ends = pipe
        Thread.detachNewThread { Self.accepting(on: listener, until: ends, accept: accept) }
    }

    /// Stops accepting; connections already accepted go on. The accepting thread closes the listener once it wakes.
    package func stop() {
        guard !stopped.exchange(true, ordering: .relaxed) else { return }
        var byte: UInt8 = 1
        _ = write(wake, &byte, 1)
    }

    private static func accepting(on listener: Int32, until wake: [Int32], accept: @Sendable (Int32) -> Void) {
        defer { for descriptor in [listener] + wake { Darwin.close(descriptor) } }
        while waitForConnection(on: listener, orWake: wake[0]) {
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { continue }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            // Accepted sockets inherit the listener's non-blocking mode; a stream reads and writes blocking.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            accept(client)
        }
    }

    /// Waits until `listener` has a connection to accept (true), or `wake` is written or the wait fails (false).
    private static func waitForConnection(on listener: Int32, orWake wake: Int32) -> Bool {
        var fds = [
            pollfd(fd: listener, events: Int16(POLLIN), revents: 0), pollfd(fd: wake, events: Int16(POLLIN), revents: 0)
        ]
        repeat {
            if poll(&fds, 2, -1) < 0 {
                if errno == EINTR { continue }
                return false
            }
            if fds[1].revents != 0 { return false }
        } while fds[0].revents & Int16(POLLIN) == 0
        return true
    }
}
