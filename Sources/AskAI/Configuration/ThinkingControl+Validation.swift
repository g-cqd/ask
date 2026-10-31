extension ThinkingControl {
    func anthropicProblem(maximumTokens: Int) -> ThinkingError? {
        if let effortProblem { return effortProblem }
        if case .budget(let tokens, _) = self, tokens < 1024 || tokens >= maximumTokens {
            return .invalidControl("a native budget must be at least 1024 and less than the request output limit")
        }
        return nil
    }

    var responsesProblem: ThinkingError? {
        if let effortProblem { return effortProblem }
        switch self {
            case .budget, .betweenTools, .adaptive:
                return .unsupportedProtocol("a native thinking mode on the Responses API")
            case .disabled, .effort: return nil
        }
    }

    private var effortProblem: ThinkingError? {
        let level: ThinkingLevel?
        switch self {
            case .effort(let value): level = value
            case .budget(_, let value): level = value
            default: level = nil
        }
        guard let level, !level.isEffort else { return nil }
        return .invalidControl("default and off are not named effort values")
    }
}
