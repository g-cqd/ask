/// The JSON payload of a node's sealed list (`docs/protocol/gateway.md`, "The sealed list"): the sessions running on this computer,
/// and the canonical folders a controller may start a new session in.
struct SharedNodeList: Codable, Sendable, Equatable {
    let sessions: [ViewerEndpoint.Description]
    let folders: [String]
}
