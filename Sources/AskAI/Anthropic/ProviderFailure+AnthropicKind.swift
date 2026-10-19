internal import AemiJSON

extension ProviderFailure.Kind {
    init(wire: String, message: String = "") {
        if wire == "invalid_request_error", Self.describesContextOverflow(message) {
            self = .contextOverflow
            return
        }
        switch wire {
            case "overloaded_error": self = .overloaded
            case "rate_limit_error": self = .rateLimited
            case "authentication_error": self = .authentication
            case "permission_error": self = .permission
            case "invalid_request_error": self = .invalidRequest
            case "not_found_error": self = .notFound
            case "request_too_large": self = .requestTooLarge
            case "api_error": self = .server
            default: self = .other(wire)
        }
    }
}
