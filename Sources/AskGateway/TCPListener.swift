internal import Darwin

/// A TCP listener bound to one IPv4 address (ADR-0170, "Two doors"): the nodes' door on a LAN address, never every interface; the
/// controllers' on 127.0.0.1. Each connection it accepts is handed over as a ``TCPStream``.
package final class TCPListener: Sendable {
    /// The port it listens on, known as soon as it is made.
    package let port: UInt16
    private let acceptor: SocketAcceptor

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
        if let failed {
            let code = errno
            Darwin.close(listener)
            throw TCPStream.Failure(call: failed, code: code)
        }
        self.port = UInt16(bigEndian: address.sin_port)
        acceptor = try SocketAcceptor(listener: listener) { accept(TCPStream(descriptor: $0)) }
    }

    /// Stops accepting; connections already accepted go on.
    package func stop() { acceptor.stop() }
}
