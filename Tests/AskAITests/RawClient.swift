internal import Darwin
internal import Foundation

@testable import AskAI

/// A blocking client that sends exactly the bytes it is given to a loopback port and returns what comes back until
/// the server closes: the one way to send a listener a request no browser would.
enum RawClient {
    /// The response to `request`, or nil when nothing could be connected or read.
    static func send(_ request: String, to port: UInt16, timeout: Int = 3) async -> String? {
        await Task.detached { exchange(Array(request.utf8), port: port, timeout: timeout, hold: false) }.value
    }

    /// A GET for `target` with an allowed host.
    static func get(_ target: String, port: UInt16, host: String? = nil) async -> String? {
        await send("GET \(target) HTTP/1.1\r\nHost: \(host ?? "127.0.0.1:\(port)")\r\n\r\n", to: port)
    }

    /// Connects and sends nothing for `seconds`, as a stalled browser tab does.
    static func stall(port: UInt16, seconds: Int) async {
        _ = await Task.detached { exchange([], port: port, timeout: seconds, hold: true) }.value
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

    private static func exchange(_ bytes: [UInt8], port: UInt16, timeout: Int, hold: Bool) -> String? {
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
        return hold ? "" : String(decoding: reply, as: UTF8.self)
    }
}
