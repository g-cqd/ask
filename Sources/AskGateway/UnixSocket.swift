internal import Darwin

/// Unix domain stream sockets, as each ask's viewer endpoint offers its screen on (ADR-0170).
package enum UnixSocket {
    /// A connection to the socket at `path`.
    /// - Throws: ``TCPStream/Failure`` naming the call that failed.
    package static func connect(to path: String) throws(TCPStream.Failure) -> TCPStream {
        let client = try open(path) { descriptor, address, length in
            unsafe Darwin.connect(descriptor, address, length) == 0 ? nil : "connect"
        }
        return TCPStream(descriptor: client)
    }

    /// A socket listening at `path`, replacing any file there, made with no access for anyone but the owner.
    /// - Throws: ``TCPStream/Failure`` naming the call that failed.
    package static func listen(at path: String) throws(TCPStream.Failure) -> Int32 {
        unlink(path)
        let previous = umask(0o077)
        defer { umask(previous) }
        return try open(path) { descriptor, address, length in
            if unsafe bind(descriptor, address, length) != 0 { return "bind" }
            return Darwin.listen(descriptor, 16) != 0 ? "listen" : nil
        }
    }

    /// `path`'s address, and a socket opened on it by ``Sockets/open(family:address:_:)``.
    private static func open(
        _ path: String,
        _ use: (Int32, UnsafeMutablePointer<sockaddr>, socklen_t) -> String?
    ) throws(TCPStream.Failure) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw TCPStream.Failure(call: "socket path", code: ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in bytes.enumerated() { raw[index] = byte }
        }
        return try Sockets.open(family: AF_UNIX, address: &address, use)
    }
}
