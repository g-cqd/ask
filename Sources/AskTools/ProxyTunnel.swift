internal import Darwin
internal import Foundation

/// One connection to the provider proxy (roadmap 0021), on a thread of its own: the request head is read, ``ProxyRequest`` decides,
/// and an allowed tunnel is connected and relayed both ways until both sides close; anything else gets its refusal and is closed.
enum ProxyTunnel {
    /// The most a request head may be: a CONNECT line and a few headers.
    static let headLimit = 8192
    /// How long a client gets to send its request, and a connection to the provider to open.
    static let waitSeconds = 10

    static func serve(_ client: Int32, allowing allowed: Set<ProxyRequest.Target>) {
        defer { close(client) }
        noSignalOnClose(client)
        setTimeout(client, seconds: waitSeconds)
        guard let (head, rest) = readHead(client) else {
            reply(client, 400, "Bad Request")
            return
        }
        switch ProxyRequest.decide(head, allowing: allowed) {
            case .refuse(let status, let reason): reply(client, status, reason)
            case .tunnel(let target):
                guard let upstream = connect(to: target) else {
                    reply(client, 502, "Bad Gateway: \(target.host):\(target.port) could not be reached")
                    return
                }
                defer { close(upstream) }
                setTimeout(client, seconds: 0)
                guard writeAll(client, Array("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)),
                    rest.isEmpty || writeAll(upstream, rest)
                else { return }
                relay(client, upstream)
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
        _ = writeAll(client, Array("HTTP/1.1 \(status) \(flat)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
    }

    /// A connected socket to `target`, trying each of its addresses; nil when none answers.
    private static func connect(to target: ProxyRequest.Target) -> Int32? {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(target.host, String(target.port), &hints, &list) == 0, let list else { return nil }
        defer { freeaddrinfo(list) }
        var entry: UnsafeMutablePointer<addrinfo>? = list
        while let current = entry {
            let candidate = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if candidate >= 0 {
                _ = fcntl(candidate, F_SETFD, FD_CLOEXEC)
                noSignalOnClose(candidate)
                setTimeout(candidate, seconds: waitSeconds)
                if Darwin.connect(candidate, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0 {
                    setTimeout(candidate, seconds: 0)
                    return candidate
                }
                close(candidate)
            }
            entry = current.pointee.ai_next
        }
        return nil
    }

    /// Copies each side to the other until both have closed; a side that closes has its end passed on as a half-close.
    private static func relay(_ client: Int32, _ upstream: Int32) {
        var open = [true, true]  // client to upstream, upstream to client
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

    /// A write to a closed peer fails with EPIPE instead of killing ask with SIGPIPE.
    private static func noSignalOnClose(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Reads and writes on `fd` give up after `seconds`; zero waits for ever, as a tunnel's relay does.
    private static func setTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
}
