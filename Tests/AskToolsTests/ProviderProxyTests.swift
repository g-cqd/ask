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

    /// The request head for a tunnel to `port` on this machine, with `proxy`'s credential, as a client given its address sends it.
    private static func tunnelHead(_ proxy: ProviderProxy, _ port: Int, credential: String? = nil) -> String {
        let token = Data((credential ?? "ask:\(proxy.token)").utf8).base64EncodedString()
        return "CONNECT 127.0.0.1:\(port) HTTP/1.1\r\nProxy-Authorization: Basic \(token)\r\n\r\n"
    }

    /// Security audit 2026-11-22, HIGH-07: the port can be found by any program on this machine; only those given the address can
    /// use the tunnel.
    @Test func `a CONNECT without the proxy's credential, or with another, is refused with 407 and connects nowhere`()
        throws
    {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "127.0.0.1", port: upstream)])
        defer { proxy.stop() }
        let bare = try exchange(proxy.port, ["CONNECT 127.0.0.1:\(upstream) HTTP/1.1\r\n\r\n"])
        #expect(bare.hasPrefix("HTTP/1.1 407") && bare.contains("Proxy-Authenticate: Basic"), "\(bare)")
        let wrong = try exchange(proxy.port, [Self.tunnelHead(proxy, upstream, credential: "ask:guessed")])
        #expect(wrong.hasPrefix("HTTP/1.1 407"))
        let address = try #require(proxy.environment["HTTPS_PROXY"])
        #expect(
            address == "http://ask:\(proxy.token)@127.0.0.1:\(proxy.port)",
            "the credential is in the address commands get"
        )
        let other = try ProviderProxy(allowing: [])
        defer { other.stop() }
        #expect(other.token != proxy.token && proxy.token.count >= 32)
        let reply = try exchange(proxy.port, [Self.tunnelHead(proxy, upstream), "ping"])
        #expect(
            reply.hasPrefix("HTTP/1.1 200") && reply.hasSuffix("ping"),
            "the echo server was still free: nothing reached it before"
        )
    }

    /// A socket connected to the proxy on `port`, sending nothing.
    private func dial(_ port: Int) throws -> Int32 {
        let client = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                try #require(Darwin.connect(client, raw, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0)
            }
        }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return client
    }

    /// Security audit 2026-11-22, HIGH-07: connections beyond the cap are closed, not each given a thread.
    @Test func `beyond its most tunnels at once a connection is closed unanswered, and served again once they end`()
        throws
    {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "127.0.0.1", port: upstream)])
        defer { proxy.stop() }
        let held = try (0 ..< ProviderProxy.maximumTunnels).map { _ in try dial(proxy.port) }
        usleep(200_000)
        let over = try dial(proxy.port)
        var byte: UInt8 = 0
        #expect(read(over, &byte, 1) == 0, "closed without a reply")
        close(over)
        for client in held { close(client) }
        usleep(300_000)
        let reply = try exchange(proxy.port, [Self.tunnelHead(proxy, upstream), "ping"])
        #expect(reply.hasPrefix("HTTP/1.1 200") && reply.hasSuffix("ping"))
    }

    /// A connection to the proxy; what it reads after sending `text`, up to `limit` bytes or a pause.
    private func exchange(_ port: Int, _ messages: [String], limit: Int = 4096, pause: Double = 0) throws -> String {
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
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var received: [UInt8] = []
        if pause > 0 { usleep(useconds_t(pause * 1_000_000)) }
        for (index, message) in messages.enumerated() {
            _ = message.utf8CString.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count - 1) }
            // TCP may split what comes back, or send it later than one read waits: read until the reply to this message is whole
            // (a head ends with a blank line; an echo ends with what was sent), the peer closes, or the timeout passes.
            let whole = index == 0 ? Array("\r\n\r\n".utf8) : Array(message.utf8)
            var buffer = [UInt8](repeating: 0, count: limit)
            while !received.ends(with: whole), received.count < limit {
                let count = read(client, &buffer, buffer.count)
                guard count > 0 else { break }
                received += buffer.prefix(count)
            }
        }
        return String(decoding: received, as: UTF8.self)
    }

    @Test func `a tunnel to an allowed target relays both ways`() throws {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "127.0.0.1", port: upstream)])
        defer { proxy.stop() }
        let reply = try exchange(proxy.port, [Self.tunnelHead(proxy, upstream), "ping"])
        #expect(reply.hasPrefix("HTTP/1.1 200 "), "\(reply)")
        #expect(reply.hasSuffix("ping"), "\(reply)")
    }

    @Test func `a client slow to send its request is waited for`() throws {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "127.0.0.1", port: upstream)])
        defer { proxy.stop() }
        let reply = try exchange(proxy.port, [Self.tunnelHead(proxy, upstream), "ping"], pause: 0.3)
        #expect(reply.hasPrefix("HTTP/1.1 200 "), "\(reply)")
    }

    @Test func `a target it does not allow is refused with 403`() throws {
        let upstream = try echoServer()
        let proxy = try ProviderProxy(allowing: [.init(host: "api.anthropic.com", port: 443)])
        defer { proxy.stop() }
        let reply = try exchange(proxy.port, [Self.tunnelHead(proxy, upstream)])
        #expect(reply.hasPrefix("HTTP/1.1 403 "), "\(reply)")
    }

    /// A proxy stopped before its accept thread first ran must not accept on its old descriptor once another socket has its number: it
    /// took connections meant for a server made after it (the tunnel test's flake, under load).
    @Test func `a stopped proxy takes no connection meant for a socket made after it`() throws {
        for _ in 0 ..< 40 {
            let proxy = try ProviderProxy(allowing: [])
            proxy.stop()
            let upstream = try echoServer()
            #expect(try exchange(upstream, ["ping"]) == "ping")
        }
    }

    @Test func `once stopped, its port takes no connection`() throws {
        let proxy = try ProviderProxy(allowing: [])
        let port = proxy.port
        proxy.stop()
        var refused = false
        // The accept thread closes the port once it wakes: give it a moment.
        for _ in 0 ..< 100 where !refused {
            let client = socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(UInt16(port).bigEndian)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(client)
            refused = connected != 0
            if !refused { usleep(10_000) }
        }
        #expect(refused)
    }

    @Test func `it listens on localhost, on a port of its own`() throws {
        let proxy = try ProviderProxy(allowing: [])
        defer { proxy.stop() }
        #expect(proxy.port > 0)
        #expect(proxy.environment["HTTPS_PROXY"] == "http://ask:\(proxy.token)@127.0.0.1:\(proxy.port)")
        #expect(proxy.environment["https_proxy"] == proxy.environment["HTTPS_PROXY"])
        #expect(proxy.environment["ALL_PROXY"] == proxy.environment["HTTPS_PROXY"])
        #expect(proxy.environment["NO_PROXY"] == "")
    }
}

extension Array where Element == UInt8 {
    fileprivate func ends(with suffix: [UInt8]) -> Bool {
        count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix
    }
}
