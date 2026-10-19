extension SignInError {
    /// A token endpoint failure as a sign-in failure: its status or its kind, never its body.
    init(_ error: CodexAuthError) {
        switch error {
            case .tokenEndpoint(let status, _): self = .rejected(status: status)
            case .invalidResponse: self = .invalidResponse("tokens")
            case .noAccountID: self = .invalidResponse("account")
            case .transport(let detail): self = .transport(detail)
        }
    }
}
