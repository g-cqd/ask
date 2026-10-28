/// One entry of an OpenAI-style `GET /models` answer, as far as the services probed on 2026-10-20 differ.
///
/// Every field is read leniently: one entry or one figure of the wrong type costs only itself.
struct ListedModel: Decodable, Sendable {
    let id: String?
    /// Spettro's name for the window (`context_window`), per its documentation; not probed with a key.
    let contextWindow: Lenient<Int>?
    /// OpenRouter's: the most the model can take, whoever serves it.
    let contextLength: Lenient<Int>?
    let topProvider: Lenient<Route>?
    /// Hugging Face's router: each service that can serve the model, with the window it gives.
    let providers: Lenient<[Lenient<Route>]>?
    /// OpenRouter's `architecture`, whose `modality` reads `text+image->text`: what goes in, then what comes out.
    let architecture: Lenient<Architecture>?

    /// The part of OpenRouter's `architecture` ask reads.
    struct Architecture: Decodable, Sendable {
        let modality: String?

        /// Whether the output side names something other than text (`text->image`): no use for a chat loop. Nil when it does not say.
        var givesText: Bool? {
            guard let output = modality?.split(separator: ">", maxSplits: 1).last, modality?.contains("->") == true
            else { return nil }
            return output.split(separator: "+").contains("text")
        }
    }

    /// A service that serves the model: OpenRouter's `top_provider` and each of Hugging Face's `providers` share this shape.
    struct Route: Decodable, Sendable {
        let status: String?
        let contextLength: Lenient<Int>?
        let maxCompletionTokens: Lenient<Int>?

        enum CodingKeys: String, CodingKey {
            case status
            case contextLength = "context_length"
            case maxCompletionTokens = "max_completion_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, providers, architecture
        case contextWindow = "context_window"
        case contextLength = "context_length"
        case topProvider = "top_provider"
    }
}
