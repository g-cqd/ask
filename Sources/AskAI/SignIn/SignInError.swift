/// Why a browser sign-in did not produce a key. Descriptions name the field or status, never a secret or a URL.
public enum SignInError: Error, Sendable, Equatable, CustomStringConvertible {
    /// No answer arrived, with the transport's description.
    case transport(String)
    /// The server refused with this status.
    case rejected(status: Int)
    /// An answer that cannot be trusted: this field is missing, malformed or unsafe.
    case invalidResponse(String)
    /// The server named a place to send the user or the key that is not where this provider lives.
    case untrustedURL(String)
    /// The server ended the session before the user finished.
    case expired
    /// The user said no in the browser.
    case denied
    /// The user did not finish in time.
    case timedOut
    /// The run was cancelled.
    case cancelled

    public var description: String {
        switch self {
            // @dl:accept -- an enum describing each of its cases in a sentence: the three error enums share this shape, and the sentences are the data
            case .transport(let detail): "no answer from the server: \(detail)"
            case .rejected(let status): "the server refused with status \(status)"
            case .invalidResponse(let field):
                "the server's answer cannot be trusted: \"\(field)\" is missing or malformed"
            case .untrustedURL(let field):
                "the server named a place it does not own in \"\(field)\"; nothing was opened"
            case .expired: "the sign-in session expired; run login again"
            case .denied: "the sign-in was denied in the browser"
            case .timedOut: "the sign-in was not finished in time; run login again"
            case .cancelled: "the sign-in was cancelled"
        }
    }
}
