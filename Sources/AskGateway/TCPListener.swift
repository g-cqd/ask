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
    ///   - subnet: when set, any peer outside this IPv4 subnet is closed before a byte is read.
    ///   - accept: receives each connection, on the accepting thread: it must hand the stream over, not serve it there.
    /// - Throws: ``TCPStream/Failure`` naming the call that failed.
    package init(
        host: String,
        port: UInt16,
        subnet: IPv4Subnet? = nil,
        accept: @escaping @Sendable (TCPStream) -> Void
    ) throws(TCPStream.Failure) {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw TCPStream.Failure(call: "inet_pton", code: EINVAL)
        }
        let listener = try Sockets.open(family: AF_INET, address: &address) { descriptor, raw, length in
            var reuse: Int32 = 1
            _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            if unsafe bind(descriptor, raw, length) != 0 { return "bind" }
            if listen(descriptor, 64) != 0 { return "listen" }
            var named = length
            return unsafe getsockname(descriptor, raw, &named) != 0 ? "getsockname" : nil
        }
        self.port = UInt16(bigEndian: address.sin_port)
        acceptor = try SocketAcceptor(listener: listener) { client in
            if let subnet {
                guard let peer = IPv4Subnet.peerAddress(of: client), subnet.contains(peer) else {
                    Darwin.close(client)
                    return
                }
            }
            accept(TCPStream(descriptor: client))
        }
    }

    /// Stops accepting; connections already accepted go on.
    package func stop() { acceptor.stop() }
}
