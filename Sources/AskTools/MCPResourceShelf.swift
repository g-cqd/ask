internal import AskMCP
internal import Synchronization

/// The connected servers that say they have resources, with the connection each is read through (roadmap 0067).
final class MCPResourceShelf: Sendable {
    private let servers = Mutex<[String: MCPConnection]>([:])

    /// Makes `connection` the one `server` is read through, or forgets `server` for nil.
    func set(_ server: String, _ connection: MCPConnection?) {
        servers.withLock { $0[server] = connection }
    }

    /// The servers on the shelf, in name order.
    var names: [String] { servers.withLock { $0.keys.sorted() } }

    func connection(_ server: String) -> MCPConnection? { servers.withLock { $0[server] } }
}
