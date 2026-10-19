/// Who issued a thinking block's signature, so reasoning goes back only to the protocol that produced it.
///
/// Anthropic signs its reasoning and refuses a signature it did not issue. Another protocol's reasoning, such as a
/// Responses reasoning item, is opaque to every other provider. A protocol other than Anthropic's therefore stores
/// what it needs to replay its reasoning behind a marker no Anthropic signature can start with, and each encoder sends
/// only what it recognises as its own (ADR-0033). An unmarked signature is Anthropic's; an empty one is nobody's.
enum ReasoningProvenance {
    private static let marker = "ask-foreign:"

    /// `payload`, marked as issued by the protocol `scheme`.
    static func mark(scheme: String, payload: String) -> String { marker + scheme + ":" + payload }

    /// Whether `signature` was issued by a protocol other than Anthropic's.
    static func isForeign(_ signature: String) -> Bool { signature.hasPrefix(marker) }

    /// What `scheme` stored in `signature`, or nil when another protocol, or none, issued it.
    static func payload(of signature: String, scheme: String) -> String? {
        let prefix = marker + scheme + ":"
        return signature.hasPrefix(prefix) ? String(signature.dropFirst(prefix.count)) : nil
    }
}
