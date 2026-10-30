/// Whether the system has a route to the network (roadmap 0141), so a failed request can wait for the network to come back instead of
/// spending its retries in seconds while the Mac is offline.
public protocol NetworkPath: Sendable {
    /// Whether a route is usable now.
    func isSatisfied() async -> Bool
    /// Returns true once a route is usable, or false after `limit` or when the calling task is cancelled.
    func waitUntilSatisfied(atMost limit: Duration) async -> Bool
}
