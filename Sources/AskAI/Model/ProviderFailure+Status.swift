extension ProviderFailure.Kind {
    /// The kind an HTTP status means when the body says nothing more specific.
    init(status: Int?) {
        switch status {
            case 400: self = .invalidRequest
            case 401: self = .authentication
            case 403: self = .permission
            case 404: self = .notFound
            case 413: self = .requestTooLarge
            case 429: self = .rateLimited
            case 503, 529: self = .overloaded
            case let code? where (500 ... 599).contains(code): self = .server
            default: self = .other(status.map(String.init) ?? "unknown")
        }
    }
}
