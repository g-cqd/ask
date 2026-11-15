internal import AemiJSON

/// What the client said it can show (ACP v1, Initialization, `clientCapabilities`), of what ask sends only to a client that said
/// so: an object under the name advertises it; absent or null does not.
struct ACPClientCapabilities: Sendable, Equatable {
    /// `session.notices`: live notices.
    var notices = false
    /// `session.compaction`: compactions as entities of the timeline.
    var compaction = false
    /// `elicitation.form`: a form for the person to fill.
    var form = false

    init() {}

    /// What the `params` of `initialize` advertise.
    init(initialize params: JSON?) {
        guard let capabilities = params?["clientCapabilities"] else { return }
        notices = capabilities["session"]["notices"].isObject
        compaction = capabilities["session"]["compaction"].isObject
        form = capabilities["elicitation"]["form"].isObject
    }
}
