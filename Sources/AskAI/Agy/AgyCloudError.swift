/// A Cloud Code failure, described without the server's body, which can carry addresses and tokens.
public enum AgyCloudError: Error, Sendable, Equatable, CustomStringConvertible {
    case refused(status: Int, reason: String?)
    case invalidResponse
    case noProject(reasons: [String])

    public var description: String {
        switch self {
            case .refused(let status, let reason):
                let hint =
                    status == 401
                    ? "sign in again with `ask login agy`"
                    : status == 403 ? "the account or project may not be permitted; check that `agy` works for it" : nil
                return "Antigravity refused the request (HTTP \(status)\(reason.map { ", " + $0 } ?? ""))"
                    + (hint.map { "; " + $0 } ?? "")
            case .invalidResponse: return "Antigravity answered with something ask cannot read"
            case .noProject(let reasons):
                return "This Google account has no Antigravity Cloud Code project"
                    + (reasons.isEmpty ? "" : " (ineligible: " + reasons.joined(separator: ", ") + ")")
                    + ". Finish onboarding once in the `agy` CLI with this account, then run `ask login agy` again."
        }
    }
}
