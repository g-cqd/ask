/// How Gemini 3 and later handle the thought signature of a replayed function call.
///
/// They refuse a replayed call that has none ("Function call is missing a thought_signature", HTTP 400, observed live on two models).
/// Google documents a sentinel for a call whose signature is not available, and the live probes accepted it on those models.
enum AgyThoughtSignature {
    /// Stands in for a signature that is not available. Never sent over a real one.
    static let sentinel = "skip_thought_signature_validator"

    /// Whether `model` is a Gemini of major version 3 or later: `gemini-N` or `gemini-live-N`, ignoring case.
    static func requiresSignature(model: String) -> Bool {
        var name = Substring(model.lowercased())
        guard name.hasPrefix("gemini-") else { return false }
        name = name.dropFirst("gemini-".count)
        if name.hasPrefix("live-") { name = name.dropFirst("live-".count) }
        let digits = name.prefix { $0.isASCII && $0.isNumber }
        return Int(digits).map { $0 >= 3 } ?? false
    }

    /// The provenance scheme a signature issued by `model` is stored under.
    static func scheme(model: String) -> String { AgyStreamDecoder.schemePrefix + model }
}
