internal import Darwin
internal import Foundation
internal import Synchronization

/// A TCP listener bound to one IPv4 address (ADR-0170, "Two doors"): the nodes' door on a LAN address, never every interface; the
/// controllers' on 127.0.0.1. One thread accepts, as ``ProviderProxy`` does; each connection is handed over as a ``TCPStream``.
package final class TCPListener: Sendable {
    /// The port it listens on, known as soon as it is made.
    package let port: UInt16
    private let listener: Int32
    private let wake: Int32
    private let stopped = Atomic<Bool>(false)

    /// Listens on `host:port`; port 0 picks a free one.
    /// - Parameters:
    ///   - host: a dotted IPv4 address.
    ///   - port: the port, or 0.
    ///   - accept: receives each connection, on the accepting thread: it must hand the stream over, not serve it there.
    /// - Throws: ``TCPStream/Failure`` naming the call that failed.
    package init(host: String, port: UInt16, accept: @escaping @Sendable (TCPStream) -> Void) throws(TCPStream.Failure)
    {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw TCPStream.Failure(call: "socket", code: errno) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            Darwin.close(listener)
            throw TCPStream.Failure(call: "inet_pton", code: EINVAL)
        }
        var reuse: Int32 = 1
        _ = setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let failed: String? = withUnsafeMutablePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                if unsafe bind(listener, raw, length) != 0 { return "bind" }
                if listen(listener, 64) != 0 { return "listen" }
                return unsafe getsockname(listener, raw, &length) != 0 ? "getsockname" : nil
            }
        }
        var pipe: [Int32] = [-1, -1]
        if let failed {
            let code = errno
            Darwin.close(listener)
            throw TCPStream.Failure(call: failed, code: code)
        }
        guard Darwin.pipe(&pipe) == 0 else {
            let code = errno
            Darwin.close(listener)
            throw TCPStream.Failure(call: "pipe", code: code)
        }
        for descriptor in [listener] + pipe { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)
        self.listener = listener
        self.port = UInt16(bigEndian: address.sin_port)
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

    private static func accepting(on listener: Int32, until wake: [Int32], accept: @Sendable (TCPStream) -> Void) {
        defer { for descriptor in [listener] + wake { Darwin.close(descriptor) } }
        while waitForConnection(on: listener, orWake: wake[0]) {
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { continue }
            // Accepted sockets inherit the listener's non-blocking mode; a stream reads and writes blocking.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            accept(TCPStream(descriptor: client))
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
