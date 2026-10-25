/// The protocol versions this client speaks.
enum MCPProtocolVersion {
    /// Newest first. A real server answers the version it is offered when it knows it and its own newest when it does not
    /// (probed), so the first is offered and any of these is accepted back.
    static let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    /// What this client offers.
    static var offered: String { supported[0] }
}
