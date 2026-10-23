/// A failure the provider reported. Each kind calls for a different response, so none collapse into a string.
public struct ProviderFailure: Error, Sendable, Equatable {
    /// The provider's classification.
    public enum Kind: Sendable, Equatable {
        case overloaded, rateLimited, authentication, permission, invalidRequest, notFound, requestTooLarge, server
        /// The request is longer than the model's context window. Sending it again cannot succeed; compacting
        /// the conversation first can.
        case contextOverflow
        /// The account has used what its plan allows. Unlike a rate limit, sending the request again soon cannot succeed: the
        /// provider lifts it at a set time, often hours away.
        case usageLimit
        /// The server could not verify reasoning the request sent back. The same request cannot succeed; one without that
        /// reasoning can.
        case rejectedReasoning
        /// A kind this decoder does not know, kept verbatim.
        case other(String)
    }

    public let kind: Kind
    /// The provider's message, for the user.
    public let message: String

    /// The context window the provider said the model has, when a refusal for length names it.
    public let contextWindow: Int?

    /// Seconds until a ``Kind/usageLimit`` lifts, as the provider counted them when it refused; nil when it did not say.
    public let resetsInSeconds: Int?

    /// A failure of this kind.
    public init(kind: Kind, message: String, contextWindow: Int? = nil, resetsInSeconds: Int? = nil) {
        self.kind = kind
        self.message = message
        self.contextWindow = contextWindow
        self.resetsInSeconds = resetsInSeconds
    }

    /// The longest reset time believed: a month. A server that says more is wrong or hostile, and a person is better told nothing.
    static let longestReset = 2_592_000

    /// `seconds` if it is a believable time until a limit lifts, else nil.
    static func sensibleReset(_ seconds: Int) -> Int? { (0 ... longestReset).contains(seconds) ? seconds : nil }

    /// What to tell the person: the provider's own words, and for a usage limit when it lifts.
    public var sentence: String {
        guard kind == .usageLimit, let seconds = resetsInSeconds else { return message }
        return message + "; it resets in " + Self.roughly(seconds: seconds)
    }

    /// A duration as a person says it, to the nearest minute, hour or day.
    private static func roughly(seconds: Int) -> String {
        func unit(_ count: Int, _ name: String) -> String { "about \(count) \(name)\(count == 1 ? "" : "s")" }
        let minutes = (seconds + 30) / 60
        if seconds < 60 { return "less than a minute" }
        if minutes < 60 { return unit(minutes, "minute") }
        let hours = (seconds + 1800) / 3600
        if hours < 24 || seconds < 86_400 { return unit(Swift.max(hours, 1), "hour") }
        return unit((seconds + 43_200) / 86_400, "day")
    }
}
