/// Why a provider's decoder refused part of a stream, and whether sending the request again may help.
public protocol StreamDecodingFailure: Error, Equatable {
    /// Whether the same request may succeed if sent again, such as after an overload the provider reported.
    var isRetryable: Bool { get }
}
