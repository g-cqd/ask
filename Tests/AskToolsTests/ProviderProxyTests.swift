internal import Darwin
internal import Foundation
internal import Testing

@testable import AskTools

/// The provider proxy on a real socket (roadmap 0021): it listens on localhost only, opens a tunnel to an allowed target and relays
/// both ways, and refuses anything else without connecting. A local echo server stands in for a provider.
@Suite("The provider proxy relays tunnels to allowed hosts only")
struct ProviderProxyTests {
    /// A server on 127.0.0.1 that sends back what it reads, once per connection; its port.
    private func echoServer() throws -> Int {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        try #require(listener >= 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                try #require(bind(listener, raw, length) == 0 && listen(listener, 4) == 0)
                try #require(getsockname(listener, raw, &length) == 0)
            }
        }
        Thread.detachNewThread {
            let client = accept(listener, nil, nil)
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = read(client, &buffer, buffer.count)
            if count > 0 { _ = write(client, buffer, count) }
            close(client)
            close(listener)
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// A connection to the proxy; what it reads after sending `text`, up to `limit` bytes or a pause.
    private func exchange(_ port: Int, _ messages: [String], limit: Int = 4096) throws -> String {
        let client = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(client) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                try #require(connect(client, raw, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0)
            }
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var received: [UInt8] = []
        for message in messages {
            _ = message.utf8CString.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count - 1) }
            var buffer = [UInt8](repeating: 0, count: limit)
            let count = read(client, &buffer, buffer.count)
            if count > 0 { received += buffer.prefix(count) }
        }
        return String(decoding: received, as: UTF8.self)
    }

    @Test func `a tunnel to an allowed target relays both ways`() throws {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "127.0.0.1", port: upstream)])
        defer { proxy.stop() }
        let reply = try exchange(proxy.port, ["CONNECT 127.0.0.1:\(upstream) HTTP/1.1\r\n\r\n", "ping"])
        #expect(reply.hasPrefix("HTTP/1.1 200 "), "\(reply)")
        #expect(reply.hasSuffix("ping"), "\(reply)")
    }

    @Test func `a target it does not allow is refused with 403`() throws {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "api.anthropic.com", port: 443)])
        defer { proxy.stop() }
        let reply = try exchange(proxy.port, ["CONNECT 127.0.0.1:\(upstream) HTTP/1.1\r\n\r\n"])
        #expect(reply.hasPrefix("HTTP/1.1 403 "), "\(reply)")
    }

    @Test func `it listens on localhost, on a port of its own`() throws {
        let proxy = try ProviderProxy(allowing: [])
        defer { proxy.stop() }
        #expect(proxy.port > 0)
        #expect(proxy.environment["HTTPS_PROXY"] == "http://127.0.0.1:\(proxy.port)")
        #expect(proxy.environment["https_proxy"] == proxy.environment["HTTPS_PROXY"])
        #expect(proxy.environment["ALL_PROXY"] == proxy.environment["HTTPS_PROXY"])
        #expect(proxy.environment["NO_PROXY"] == "")
    }
}
