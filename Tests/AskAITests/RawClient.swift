internal import Darwin
internal import Foundation
internal import Synchronization

@testable import AskAI

/// A blocking client that sends exactly the bytes it is given to a loopback port and returns what comes back until
/// the server closes: the one way to send a listener a request no browser would.
enum RawClient {
    /// The response to `request`, or nil when nothing could be connected or read.
    static func send(_ request: String, to port: UInt16, timeout: Int = 3) async -> String? {
        await Task.detached { exchange(Array(request.utf8), port: port, timeout: timeout) }.value
    }

    /// A GET for `target` with an allowed host.
    static func get(_ target: String, port: UInt16, host: String? = nil) async -> String? {
        await send("GET \(target) HTTP/1.1\r\nHost: \(host ?? "127.0.0.1:\(port)")\r\n\r\n", to: port)
    }

    /// A connection that is open and says nothing, as a stalled browser tab is.
    final class Held: Sendable {
        private let descriptor: Int32
        private let isClosed = Mutex(false)
        fileprivate init(_ descriptor: Int32) { self.descriptor = descriptor }

        /// Whether the server ends this connection within `seconds`, which is what it does to one that sends nothing.
        func closedByServer(within seconds: Int) async -> Bool {
            // @al:accept -- the capture list copies only an Int32, not self; SO_RCVTIMEO bounds the read, and shutdown releases the peer on failure
            await Task.detached { [descriptor] in
                var wait = timeval(tv_sec: seconds, tv_usec: 0)
                unsafe setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
                var chunk = [UInt8](repeating: 0, count: 512)
                while true {
                    // Whatever the server says on the way out is read past; the end of the connection is what counts.
                    let count = chunk.withUnsafeMutableBytes {
                        unsafe read(descriptor, $0.baseAddress, $0.count)
                    }
                    if count <= 0 { return count == 0 }
                }
            }
            .value
        }

        func close() {
            isClosed.withLock { closed in
                guard !closed else { return }
                closed = true
                // shutdown wakes a read already blocked in the server; close alone need not do that.
                _ = shutdown(descriptor, SHUT_RDWR)
                Darwin.close(descriptor)
            }
        }
    }

    /// Connects to `port` and sends nothing. The connection is made when this returns: the kernel holds it until the
    /// listener accepts, so what is sent after it is served after it.
    static func hold(port: UInt16) -> Held? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var address = LoopbackSockets.address(port: port)
        let connected = withUnsafePointer(to: &address) {
            unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(descriptor)
            return nil
        }
        return Held(descriptor)
    }

    /// Whether a connection to `port` is refused, which is what a closed listener does.
    static func refused(port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = LoopbackSockets.address(port: port)
        let result = withUnsafePointer(to: &address) {
            unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result != 0
    }

    private static func exchange(_ bytes: [UInt8], port: UInt16, timeout: Int) -> String? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var wait = timeval(tv_sec: timeout, tv_usec: 0)
        unsafe setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        var address = LoopbackSockets.address(port: port)
        let connected = withUnsafePointer(to: &address) {
            unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                unsafe connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        if !bytes.isEmpty { _ = bytes.withUnsafeBytes { unsafe write(descriptor, $0.baseAddress, $0.count) } }
        var reply: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { unsafe read(descriptor, $0.baseAddress, $0.count) }
            if count <= 0 { break }
            reply += chunk[0 ..< count]
        }
        return String(decoding: reply, as: UTF8.self)
    }
}
