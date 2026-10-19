internal import Darwin

/// The BSD socket calls the callback listener needs, and the only place that makes them. A browser's callback is one
/// request on this machine, so a few calls on sockets that are already loaded replace a server framework.
enum LoopbackSockets {
    /// A socket listening on `127.0.0.1:port` and the port it holds; port 0 asks for any free one.
    /// - Throws: ``LoopbackError/bindFailed(errno:)``.
    static func listen(port: UInt16) throws(LoopbackError) -> (descriptor: Int32, port: UInt16) {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .bindFailed(errno: errno) }
        var on: Int32 = 1
        unsafe setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        // @dl:accept -- the test client makes the same BSD calls to connect that the listener makes to bind; the call dance is the API's
        var address = address(port: port)
        let bound = withUnsafePointer(to: &address) {
            unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, 8) == 0 else {
            let failure = errno
            close(descriptor)
            throw .bindFailed(errno: failure)
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        return (descriptor, port == 0 ? boundPort(of: descriptor) : port)
    }

    /// `127.0.0.1:port` as a socket address.
    static func address(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7f00_0001).bigEndian
        return address
    }

    /// Waits up to `milliseconds` for a connection, and accepts it.
    static func accept(_ listener: Int32, milliseconds: Int32) -> Int32? {
        var watched = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard unsafe poll(&watched, 1, milliseconds) > 0 else { return nil }
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return nil }
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        unsafe setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: 1, tv_usec: 0)
        unsafe setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        unsafe setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        return client
    }

    /// The request head from `client`: bytes up to and including the blank line, or whatever arrived by `limit`.
    /// - Returns: nil when nothing arrived before the timeout.
    static func head(of client: Int32, limit: Int) -> [UInt8]? {
        var received: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 1024)
        while received.count <= limit {
            let count = chunk.withUnsafeMutableBytes { unsafe read(client, $0.baseAddress, $0.count) }
            if count <= 0 { break }
            let from = Swift.max(0, received.count - 3)
            received += chunk[0 ..< count]
            if endsHead(received, from: from) { break }
        }
        return received.isEmpty ? nil : received
    }

    /// Writes all of `bytes`, giving up quietly if the peer has gone.
    static func write(_ bytes: [UInt8], to client: Int32) {
        var sent = 0
        while sent < bytes.count {
            let count = bytes.withUnsafeBytes {
                unsafe Darwin.write(client, $0.baseAddress! + sent, $0.count - sent)
            }
            if count <= 0 { return }
            sent += count
        }
    }

    /// Whether the blank line that ends a request head occurs in `bytes` at or after `from`.
    private static func endsHead(_ bytes: [UInt8], from: Int) -> Bool {
        guard bytes.count >= 4 else { return false }
        return (from ... bytes.count - 4)
            .contains {
                bytes[$0] == 13 && bytes[$0 + 1] == 10 && bytes[$0 + 2] == 13 && bytes[$0 + 3] == 10
            }
    }

    private static func boundPort(of descriptor: Int32) -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { unsafe getsockname(descriptor, $0, &length) }
        }
        return UInt16(bigEndian: address.sin_port)
    }
}
