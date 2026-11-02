internal import AskMCP
internal import Synchronization

/// The connected servers that say they have resources, with the connection each is read through (roadmap 0067), and the resources ask
/// follows on each: those a message attached, where the server offers `resources/subscribe`.
final class MCPResourceShelf: Sendable {
    private struct Shelved {
        let connection: MCPConnection
        let subscribable: Bool
        var followed: Set<String> = []
    }

    private let servers = Mutex<[String: Shelved]>([:])

    /// Makes `connection` the one `server` is read through, or forgets `server` for nil; `subscribable` when it offers subscriptions.
    func set(_ server: String, _ connection: MCPConnection?, subscribable: Bool = false) {
        servers.withLock { $0[server] = connection.map { Shelved(connection: $0, subscribable: subscribable) } }
    }

    /// The servers on the shelf, in name order.
    var names: [String] { servers.withLock { $0.keys.sorted() } }

    func connection(_ server: String) -> MCPConnection? { servers.withLock { $0[server]?.connection } }

    /// Follows `uri` on `server`: the connection to subscribe through the first time, nil when it is followed already or cannot be.
    func follow(_ server: String, _ uri: String) -> MCPConnection? {
        servers.withLock { servers in
            guard let shelved = servers[server], shelved.subscribable, !shelved.followed.contains(uri) else {
                return nil
            }
            servers[server]?.followed.insert(uri)
            return shelved.connection
        }
    }

    /// Whether ask follows `uri` on `server`.
    func follows(_ server: String, _ uri: String) -> Bool {
        servers.withLock { $0[server]?.followed.contains(uri) ?? false }
    }
}
