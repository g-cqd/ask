internal import Darwin

/// Waits for a local port to accept connections. A refused connection carries no event to wait on, so this
/// tries again with backoff, from 50 ms up to 1 s, on the injected clock.
///
/// Each attempt is bounded at 250 ms. A port that is bound but not listening yet, a server's state between
/// `bind` and `listen`, silently drops IPv4 connections on macOS, and a blocking connect then hangs for 7.9 s
/// (probed, diary 12).
enum PortWait {
    /// Waits until something accepts TCP connections on `port` at 127.0.0.1 or ::1.
    /// - Returns: true once a connection succeeded; false when the task was cancelled first.
    static func until(open port: Int, clock: any Clock<Duration>) async -> Bool {
        var delay = Duration.milliseconds(50)
        while !Task.isCancelled {
            if accepts(port) { return true }
            guard (try? await clock.sleep(for: delay)) != nil else { return false }
            delay = Swift.min(delay * 2, .seconds(1))
        }
        return false
    }

    /// Whether a connection to `port` on the loopback addresses succeeds now.
    static func accepts(_ port: Int) -> Bool {
        guard (1 ... 65_535).contains(port) else { return false }
        var v4 = loopback(port)
        var v6 = sockaddr_in6()
        v6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        v6.sin6_family = sa_family_t(AF_INET6)
        v6.sin6_port = in_port_t(UInt16(port).bigEndian)
        v6.sin6_addr = in6addr_loopback
        return connects(&v4, family: AF_INET) || connects(&v6, family: AF_INET6)
    }

    /// 127.0.0.1 at `port`.
    static func loopback(_ port: Int) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        return address
    }

    private static func connects<Address>(_ address: inout Address, family: Int32) -> Bool {
        let socket = Darwin.socket(family, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        _ = fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK)
        let started = withUnsafePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe connect(socket, $0, socklen_t(MemoryLayout<Address>.size))
            }
        }
        if started == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var ready = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
        guard poll(&ready, 1, 250) == 1 else { return false }
        var failure: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(socket, SOL_SOCKET, SO_ERROR, &failure, &length) == 0 else { return false }
        return failure == 0
    }
}
