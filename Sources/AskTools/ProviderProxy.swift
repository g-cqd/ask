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
    private let listener: Int32
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
        _ = fcntl(listener, F_SETFD, FD_CLOEXEC)
        self.listener = listener
        port = Int(UInt16(bigEndian: address.sin_port))
        let allowList = AllowList(allowed)
        self.allowList = allowList
        // The loop ends when ``stop()`` closes the listener: accept then fails with something other than an interruption.
        Thread.detachNewThread {
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    return
                }
                _ = fcntl(client, F_SETFD, FD_CLOEXEC)
                Thread.detachNewThread { ProxyTunnel.serve(client, allowing: allowList.current) }
            }
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

    /// Stops accepting; tunnels already open run to their end.
    public func stop() {
        guard !stopped.exchange(true, ordering: .relaxed) else { return }
        shutdown(listener, SHUT_RDWR)
        close(listener)
    }

    deinit { stop() }
}
