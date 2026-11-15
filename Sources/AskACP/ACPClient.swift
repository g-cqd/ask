internal import AemiJSON

/// What a turn needs of the client: to tell it what happens, and to ask it what only its person can answer.
struct ACPClient: Sendable {
    /// Sends one `session/update`, whose `params` these are.
    let notify: @Sendable (JSONValue) async -> Void
    /// Asks `session/request_permission` with these `params`: the result, or nil when the client gave none (it refused the
    /// request, or has gone).
    let requestPermission: @Sendable (JSONValue) async -> JSON?
}
