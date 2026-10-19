extension ProviderFailure.Kind {
    /// The kind an OpenAI-compatible server means, from the error `type` it names and else from an HTTP status.
    ///
    /// Servers word their types differently (`rate_limit_exceeded`, `server_error`, `invalid_request_error`), so the
    /// type is matched by what it contains, and a numeric status decides when the type says nothing known.
    init(openAIType type: String?, status: Int?) {
        let named = type?.lowercased() ?? ""
        switch true {
            case named.contains("rate_limit"), named.contains("quota"): self = .rateLimited
            case named.contains("overloaded"): self = .overloaded
            case named.contains("server_error"), named.contains("internal"): self = .server
            case named.contains("authentication"), named.contains("invalid_api_key"): self = .authentication
            case named.contains("permission"): self = .permission
            case named.contains("not_found"): self = .notFound
            case named.contains("invalid_request"): self = .invalidRequest
            default: self = Self(status: status, unknown: type)
        }
    }

    private init(status: Int?, unknown type: String?) {
        switch status {
            case 400: self = .invalidRequest
            case 401: self = .authentication
            case 403: self = .permission
            case 404: self = .notFound
            case 413: self = .requestTooLarge
            case 429: self = .rateLimited
            case 503, 529: self = .overloaded
            case let code? where (500 ... 599).contains(code): self = .server
            default: self = .other(type ?? status.map(String.init) ?? "unknown")
        }
    }
}
