extension ProviderFailure {
    /// Whether the provider says the same request may succeed later: overloaded, rate limited or a server error.
    public var isTransient: Bool {
        switch kind {
            case .overloaded, .rateLimited, .server: true
            default: false
        }
    }

    /// Whether a response with `status` and the reason it gave is worth retrying: 408, 429, every 5xx, or a
    /// reason ``isTransient`` says so of.
    public static func isRetryable(status: Int, failure: ProviderFailure?) -> Bool {
        // A usage limit arrives as a 429, and nothing sent in the next minute will change its answer.
        if failure?.kind == .usageLimit { return false }
        return status == 408 || status == 429 || (500 ... 599).contains(status) || failure?.isTransient == true
    }
}
