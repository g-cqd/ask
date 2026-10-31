internal import Synchronization

/// The run's providers, for the `provider` network level (roadmap 0021): ask's composition says which hosts they are, and a command
/// under the level is given the proxy's address, the proxy starting on first use. One per process, as the providers are the run's.
public enum ProviderAccess {
    private static let state = Mutex<(targets: Set<ProxyRequest.Target>, proxy: ProviderProxy?)>(([], nil))

    /// Sets where the proxy lets tunnels go: the hosts of the providers this run uses. A running proxy follows at once.
    public static func allow(_ targets: Set<ProxyRequest.Target>) {
        state.withLock { state in
            state.targets = targets
            state.proxy?.allow(targets)
        }
    }

    /// The proxy variables for a command under the level, starting the proxy if it is not running; none when it cannot start, and the
    /// command then reaches nothing, the sandbox allowing localhost only.
    static func commandEnvironment() -> [String: String] {
        state.withLock { state in
            if state.proxy == nil { state.proxy = try? ProviderProxy(allowing: state.targets) }
            return state.proxy?.environment ?? [:]
        }
    }
}
