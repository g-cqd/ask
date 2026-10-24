/// Why an Antigravity sign-in or refresh failed. No case carries a token, a secret or the server's body.
public enum AgyAuthError: Error, Equatable, CustomStringConvertible {
    case invalidPastedCode
    case tokenEndpoint(status: Int, code: String?)
    case invalidResponse
    case noRefreshToken

    // @dl:accept -- describing an error enum case by case is the shape of every one; the sentences are its own
    public var description: String {
        switch self {
            case .invalidPastedCode:
                "that is not the code from this sign-in; open the URL ask printed and paste the code it shows"
            case .tokenEndpoint(let status, let code):
                "Google's token endpoint refused the request (HTTP \(status)\(code.map { ", \($0)" } ?? ""))"
                    + (code == "invalid_grant"
                        ? "; the grant is invalid, expired or already used: run `ask login agy` again" : "")
            case .invalidResponse: "Google's token endpoint answered something that is not a token response"
            case .noRefreshToken:
                "Google returned no refresh token, so the sign-in cannot be renewed: run `ask login agy` again"
        }
    }
}
