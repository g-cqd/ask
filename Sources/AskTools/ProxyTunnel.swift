internal import AskAI
internal import Darwin
internal import Foundation

/// One connection to the provider proxy (roadmap 0021), on a thread of its own: the request head is read, ``ProxyRequest`` decides,
/// and an allowed tunnel is connected and relayed both ways until both sides close; anything else gets its refusal and is closed.
enum ProxyTunnel {
    enum ConnectOutcome {
        case connected(Int32)
        case inwardRefused
        case unreachable
    }

    typealias Dialer = @Sendable (ProxyRequest.Target, ProxyRequest.Rule) -> ConnectOutcome

    /// The most a request head may be: a CONNECT line and a few headers.
    static let headLimit = 8192
    /// How long a client gets to send its request, and a connection to the provider to open.
    static let waitSeconds = 10

    static func serve(
        _ client: Int32,
        rule: ProxyRequest.Rule,
        authorization: String,
        dialer: Dialer? = nil
    ) {
        defer { close(client) }
        noSignalOnClose(client)
        setTimeout(client, seconds: waitSeconds)
        guard let (head, rest) = readHead(client) else {
            reply(client, 400, "Bad Request")
            return
        }
        switch ProxyRequest.decide(head, rule: rule, authorization: authorization) {
            case .refuse(let status, let reason): reply(client, status, reason)
            case .tunnel(let target):
                let outcome = dialer?(target, rule) ?? connect(to: target, rule: rule)
                switch outcome {
                    case .inwardRefused:
                        reply(client, 403, "Forbidden: \(target.host) resolves to a private or local address")
                    case .unreachable:
                        reply(client, 502, "Bad Gateway: \(target.host):\(target.port) could not be reached")
                    case .connected(let upstream):
                        defer { close(upstream) }
                        noSignalOnClose(upstream)
                        setTimeout(client, seconds: 0)
                        guard writeAll(client, Array("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)),
                            rest.isEmpty || writeAll(upstream, rest)
                        else { return }
                        relay(client, upstream)
                }
        }
    }

    /// The head up to its blank line, and whatever the client sent after it; nil when it is longer than ``headLimit`` or never ends.
    private static func readHead(_ client: Int32) -> (String, [UInt8])? {
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        let end = Array("\r\n\r\n".utf8)
        while bytes.count < headLimit {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return nil }
            bytes += buffer.prefix(count)
            if let range = bytes.firstRange(of: end) {
                return (String(decoding: bytes[..<range.upperBound], as: UTF8.self), Array(bytes[range.upperBound...]))
            }
        }
        return nil
    }

    private static func reply(_ client: Int32, _ status: Int, _ reason: String) {
        let flat = reason.replacing("\r", with: " ").replacing("\n", with: " ")
        let challenge = status == 407 ? "Proxy-Authenticate: Basic realm=\"ask\"\r\n" : ""
        _ = writeAll(
            client,
            Array("HTTP/1.1 \(status) \(flat)\r\n\(challenge)Content-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        )
    }

    /// Resolves `target` once and connects directly to its verified `sockaddr` without a second DNS lookup.
    /// In `.publicInternet` mode, if any resolved record is inward (and the host was not an explicit local literal), the entire
    /// target is refused with `.inwardRefused` before any `connect()` call is made (CRIT-05).
    static func connect(
        to target: ProxyRequest.Target,
        rule: ProxyRequest.Rule,
        resolvedAddressesForCheckOnly: [String]? = nil
    ) -> ConnectOutcome {
        let strictPublic = isStrictPublic(host: target.host, rule: rule)
        if let synthetic = resolvedAddressesForCheckOnly {
            return (strictPublic && synthetic.contains(where: InwardAddress.contains)) ? .inwardRefused : .unreachable
        }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(target.host, String(target.port), &hints, &list) == 0, let list else { return .unreachable }
        defer { freeaddrinfo(list) }
        if strictPublic, hasInwardRecord(list) { return .inwardRefused }
        return dialFirstAllowed(in: list, host: target.host)
    }

    private static func isStrictPublic(host: String, rule: ProxyRequest.Rule) -> Bool {
        guard case .publicInternet = rule else { return false }
        return host != "localhost" && host != "127.0.0.1" && host != "::1"
    }

    private static func hasInwardRecord(_ first: UnsafeMutablePointer<addrinfo>) -> Bool {
        var scan: UnsafeMutablePointer<addrinfo>? = first
        while let current = scan {
            if let address = numeric(unsafe current.pointee),
                InwardAddress.contains(String(address.prefix { $0 != "%" }))
            {
                return true
            }
            scan = unsafe current.pointee.ai_next
        }
        return false
    }

    private static func dialFirstAllowed(in first: UnsafeMutablePointer<addrinfo>, host: String) -> ConnectOutcome {
        var entry: UnsafeMutablePointer<addrinfo>? = first
        while let current = entry {
            let info = unsafe current.pointee
            if let address = numeric(info), !follows(host, to: String(address.prefix { $0 != "%" })) {
                entry = info.ai_next
                continue
            }
            let candidate = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if candidate >= 0 {
                _ = fcntl(candidate, F_SETFD, FD_CLOEXEC)
                noSignalOnClose(candidate)
                setTimeout(candidate, seconds: waitSeconds)
                if unsafe Darwin.connect(candidate, info.ai_addr, info.ai_addrlen) == 0 {
                    setTimeout(candidate, seconds: 0)
                    return .connected(candidate)
                }
                close(candidate)
            }
            entry = info.ai_next
        }
        return .unreachable
    }

    /// Copies each side to the other until both have closed; a side that closes has its end passed on as a half-close.
    private static func relay(_ client: Int32, _ upstream: Int32) {
        var open = [true, true]
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while open[0] || open[1] {
            var fds = [
                pollfd(fd: open[0] ? client : -1, events: Int16(POLLIN), revents: 0),
                pollfd(fd: open[1] ? upstream : -1, events: Int16(POLLIN), revents: 0)
            ]
            guard poll(&fds, 2, -1) > 0 else {
                if errno == EINTR { continue }
                return
            }
            for (index, (from, to)) in [(client, upstream), (upstream, client)].enumerated()
            where open[index] && fds[index].revents != 0 {
                let count = read(from, &buffer, buffer.count)
                if count > 0, writeAll(to, Array(buffer.prefix(count))) { continue }
                open[index] = false
                shutdown(to, SHUT_WR)
                if count < 0 { return }
            }
        }
    }

    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return false }
            sent += count
        }
        return true
    }

    private static func noSignalOnClose(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func setTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    static func follows(_ host: String, to address: String) -> Bool {
        InwardAddress.contains(host) || host == "localhost" || !InwardAddress.contains(address)
    }

    private static func numeric(_ entry: addrinfo) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(entry.ai_addr, entry.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else {
            return nil
        }
        return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
