internal import Darwin

/// Making a socket and binding or connecting it, for TCP and Unix sockets alike.
enum Sockets {
    /// A new stream socket of `family`, and `use` given it and `address` as a `sockaddr` and its length: it returns the name of the
    /// call that failed, or nil. On a failure the socket is closed, and the call and its errno thrown.
    static func open<Address>(
        family: Int32,
        address: inout Address,
        _ use: (Int32, UnsafeMutablePointer<sockaddr>, socklen_t) -> String?
    ) throws(TCPStream.Failure) -> Int32 {
        let descriptor = socket(family, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw TCPStream.Failure(call: "socket", code: errno) }
        let length = socklen_t(MemoryLayout<Address>.size)
        let failed = withUnsafeMutablePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { use(descriptor, $0, length) }
        }
        if let failed {
            let code = errno
            Darwin.close(descriptor)
            throw TCPStream.Failure(call: failed, code: code)
        }
        return descriptor
    }
}
