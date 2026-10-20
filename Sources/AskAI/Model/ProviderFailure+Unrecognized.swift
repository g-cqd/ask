internal import AemiJSON
internal import Foundation

extension ProviderFailure {
    /// The reason in an error body no provider adapter recognised, with its kind from the HTTP status.
    ///
    /// Providers phrase errors in many shapes (diary 14): `{"detail":…}` (Mistral, Cerebras), `{"error":"…"}` (xAI),
    /// a top-level `message`, OpenAI's error wrapped in an array (Gemini), or plain text (DeepSeek, Together). The
    /// first sentence found is used, else the text itself, trimmed and cut to 300 characters. Nil for an empty body
    /// or markup, such as a gateway's HTML error page.
    public init?(unrecognizedBody body: [UInt8], status: Int) {
        let message = Self.reason(in: body)
        guard !message.isEmpty else { return nil }
        self.init(kind: Kind(status: status), message: message)
    }

    private struct Shape: Decodable {
        struct Inner: Decodable { let message: String? }

        /// `error` as a sentence or as an object with a `message`.
        enum ErrorField: Decodable {
            case text(String)
            case object(Inner)

            // @dl:accept -- each of these decodes its own two wire shapes (a sentence or an object, a number or a string); a generic union would hide which shapes each accepts
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else {
                    self = .object(try container.decode(Inner.self))
                }
            }

            var message: String? {
                switch self {
                    case .text(let text): text
                    case .object(let inner): inner.message
                }
            }
        }

        let detail: String?
        let error: ErrorField?
        let message: String?

        var reason: String? { detail ?? error?.message ?? message }
    }

    private static func reason(in body: [UInt8]) -> String {
        let decoder = AemiJSON.JSONDecoder()
        let found =
            (try? decoder.decode(Shape.self, from: body))?.reason
            ?? (try? decoder.decode([Shape].self, from: body))?.first?.reason
            ?? String(decoding: body, as: UTF8.self)
        let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
        // A gateway's HTML error page is not a sentence for a person; the status says enough.
        guard !trimmed.hasPrefix("<") else { return "" }
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
    }
}
