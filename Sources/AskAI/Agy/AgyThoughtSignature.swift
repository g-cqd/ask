/// How Gemini 2.5 and later handle the thought signature of a replayed function call.
///
/// They refuse a replayed call that has none ("Function call is missing a thought_signature", HTTP 400, observed live on two Gemini 3 models and, on 2026-10-28, on
/// `gemini-2.5-flash`, `-flash-lite` and `-flash-thinking`, which the first version of this rule left out).
/// Google documents a sentinel for a call whose signature is not available, and the live probes accepted it on those models.
enum AgyThoughtSignature {
    /// Stands in for a signature that is not available. Never sent over a real one.
    static let sentinel = "skip_thought_signature_validator"

    /// Whether `model` is a Gemini of version 2.5 or later: `gemini-N` or `gemini-live-N`, ignoring case.
    static func requiresSignature(model: String) -> Bool {
        var name = Substring(model.lowercased())
        guard name.hasPrefix("gemini-") else { return false }
        name = name.dropFirst("gemini-".count)
        if name.hasPrefix("live-") { name = name.dropFirst("live-".count) }
        let digits = name.prefix { $0.isASCII && $0.isNumber }
        guard let major = Int(digits) else { return false }
        if major != 2 { return major >= 3 }
        let rest = name.dropFirst(digits.count)
        guard rest.hasPrefix(".") else { return false }
        return Int(rest.dropFirst().prefix { $0.isASCII && $0.isNumber }).map { $0 >= 5 } ?? false
    }

    /// The provenance scheme a signature issued by `model` is stored under.
    static func scheme(model: String) -> String { AgyStreamDecoder.schemePrefix + model }
}
