internal import Darwin
internal import Foundation
internal import Synchronization

/// The local proxy behind the `provider` network level (roadmap 0021): commands under it may reach only localhost (Seatbelt cannot
/// name a host), where this proxy opens HTTPS tunnels to the model providers' hosts and refuses everything else.
///
/// It listens on 127.0.0.1 on a port of its own, known as soon as it is made, because a job is started synchronously. Each connection
/// is served on a thread of its own (``ProxyTunnel``): a handful of a model's commands at a time, so blocking sockets are the plain
/// choice, with no dependency and no cost until a command first uses the level.
public final class ProviderProxy: Sendable {
    public enum StartError: Error, Equatable {
        /// A socket call failed, with its name and errno.
        case socket(String, Int32)
    }

    /// The port it listens on, on 127.0.0.1.
    public let port: Int
    /// Written once by ``stop()`` to wake the accept thread, which alone closes the listener: closed from here instead, its number
    /// could be another socket's by the time the thread next accepted, and the thread would take that socket's connections.
    private let wake: Int32
    private let stopped = Atomic<Bool>(false)
    /// Where tunnels may go; ``allow(_:)`` replaces it when the run's providers change, for tunnels opened from then on.
    private let allowList: AllowList

    /// A set every connection's thread reads when it decides.
    final class AllowList: Sendable {
        private let targets: Mutex<Set<ProxyRequest.Target>>
        init(_ targets: Set<ProxyRequest.Target>) { self.targets = Mutex(targets) }
        var current: Set<ProxyRequest.Target> { targets.withLock { $0 } }
        func replace(with targets: Set<ProxyRequest.Target>) { self.targets.withLock { $0 = targets } }
    }

    /// Starts listening.
    /// - Parameter allowed: the hosts and ports a tunnel may go to.
    /// - Throws: ``StartError`` when no socket can be bound.
    public init(allowing allowed: Set<ProxyRequest.Target>) throws(StartError) {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw .socket("socket", errno) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let failed: String? = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                if bind(listener, raw, length) != 0 { return "bind" }
                if listen(listener, 64) != 0 { return "listen" }
                return getsockname(listener, raw, &length) != 0 ? "getsockname" : nil
            }
        }
        if let failed {
            let code = errno
            close(listener)
            throw .socket(failed, code)
        }
        var pipe: [Int32] = [-1, -1]
        guard Darwin.pipe(&pipe) == 0 else {
            let code = errno
            close(listener)
            throw .socket("pipe", code)
        }
        for descriptor in [listener] + pipe { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        // A connection gone between poll and accept must not block the thread, which then could not be woken.
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)
        wake = pipe[1]
        port = Int(UInt16(bigEndian: address.sin_port))
        let allowList = AllowList(allowed)
        self.allowList = allowList
        Thread.detachNewThread { Self.accepting(on: listener, until: pipe, allowing: allowList) }
    }

    /// Serves each connection to `listener` until a byte arrives on `wake`, then closes both, and `wake`'s other end.
    private static func accepting(on listener: Int32, until wake: [Int32], allowing allowList: AllowList) {
        defer { for descriptor in [listener] + wake { close(descriptor) } }
        var fds = [
            pollfd(fd: listener, events: Int16(POLLIN), revents: 0),
            pollfd(fd: wake[0], events: Int16(POLLIN), revents: 0)
        ]
        while true {
            guard poll(&fds, 2, -1) >= 0 else {
                if errno == EINTR { continue }
                return
            }
            if fds[1].revents != 0 { return }
            guard fds[0].revents & Int16(POLLIN) != 0 else { continue }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            // It inherits the listener's non-blocking mode; a tunnel reads and writes blocking, with timeouts.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            Thread.detachNewThread { ProxyTunnel.serve(client, allowing: allowList.current) }
        }
    }

    /// What a command needs to send its traffic here: the proxy variables, in both cases, and an empty `NO_PROXY`, so nothing is sent
    /// around the proxy (it would fail anyway, the sandbox reaching localhost only).
    public var environment: [String: String] {
        let address = "http://127.0.0.1:\(port)"
        var values: [String: String] = ["NO_PROXY": "", "no_proxy": ""]
        for name in ["HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY"] {
            values[name] = address
            values[name.lowercased()] = address
        }
        return values
    }

    /// Replaces where tunnels may go; tunnels already open stay open.
    public func allow(_ targets: Set<ProxyRequest.Target>) { allowList.replace(with: targets) }

    /// Stops accepting; tunnels already open run to their end. The accept thread closes the listener once it wakes.
    public func stop() {
        guard !stopped.exchange(true, ordering: .relaxed) else { return }
        var byte: UInt8 = 1
        _ = write(wake, &byte, 1)
    }

    deinit { stop() }
}
